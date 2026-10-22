import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Encodes the share clip's picture (bible §10): 30 fps video-only MP4, H.264 1080 × 1920 where the encoder allows.
///
/// Robustness, because CI's simulator encoder stalled twice (once interleaving audio, once video-only):
/// - **Video only.** Sound is written by `ClipMuxer.writeAudio` and joined losslessly by `ClipMuxer.mux`.
/// - **Pull model.** Frames are handed to the writer's own serial queue through `requestMediaDataWhenReady(on:)`;
///   nothing polls `isReadyForMoreMediaData` from the main actor. The main actor only waits for a slot in a small
///   frame queue, with a timeout.
/// - **Probed fallback chain.** `make` first encodes a short probe with each configuration (H.264 High → H.264 Main
///   without B-frames on plain, non-IOSurface buffers → HEVC → H.264 Main 720 × 1280) and uses the first that
///   completes. The choice is cached for the session. On a device the first one always wins (~0.2 s).
@MainActor
final class ClipWriter {
    enum WriterError: LocalizedError {
        case setup(String)
        case encoding(String)
        case stalled

        var errorDescription: String? {
            switch self {
            case .setup(let detail): "Couldn't set up the video encoder (\(detail))."
            case .encoding(let detail): "The video encoder stopped (\(detail))."
            case .stalled: "The video encoder stopped responding."
            }
        }
    }

    /// One encoder setup to try.
    struct Config: Equatable, CustomStringConvertible {
        var codec: AVVideoCodecType
        var profile: String?
        var allowReordering: Bool
        var width: Int
        var height: Int
        var bitRate: Int
        /// Allocate our own non-IOSurface buffers instead of the adaptor's pool.
        var ownBuffers: Bool

        var description: String {
            "\(codec.rawValue) \(profile ?? "auto") \(width)x\(height) \(bitRate / 1000)k"
                + (allowReordering ? "" : " no-B") + (ownBuffers ? " plain-buffers" : " pool")
        }

        /// Most to least preferred. The bitrate keeps a 10 s clip under 8 MB (bible §10).
        static func chain(width: Int, height: Int, bitRate: Int) -> [Config] {
            let smallW = (width * 2 / 3) & ~1
            let smallH = (height * 2 / 3) & ~1
            return [
                Config(codec: .h264, profile: AVVideoProfileLevelH264HighAutoLevel, allowReordering: true,
                       width: width, height: height, bitRate: bitRate, ownBuffers: false),
                Config(codec: .h264, profile: AVVideoProfileLevelH264MainAutoLevel, allowReordering: false,
                       width: width, height: height, bitRate: bitRate, ownBuffers: true),
                Config(codec: .hevc, profile: nil, allowReordering: false,
                       width: width, height: height, bitRate: bitRate * 3 / 4, ownBuffers: true),
                Config(codec: .h264, profile: AVVideoProfileLevelH264MainAutoLevel, allowReordering: false,
                       width: smallW, height: smallH, bitRate: bitRate * 3 / 5, ownBuffers: true),
            ]
        }
    }

    static let fps: Int32 = 30
    /// Per-frame wait for the encoder before giving up (real clip / probe).
    static let frameTimeout: Duration = .seconds(12)
    static let probeTimeout: Duration = .seconds(3)
    private static var chosen: Config?

    let url: URL
    let config: Config
    var width: Int { config.width }
    var height: Int { config.height }
    private(set) var framesWritten = 0

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let feed = FrameFeed()
    private let queue = DispatchQueue(label: "com.pravegm.squish.clipwriter", qos: .userInitiated)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let timeout: Duration
    private let started = ContinuousClock.now

    // MARK: - Making one

    /// A started writer with the first configuration that encodes on this device (probed once per session).
    static func make(url: URL, width: Int = 1080, height: Int = 1920, bitRate: Int) async throws -> ClipWriter {
        if let chosen {
            let writer = try ClipWriter(url: url, config: chosen, timeout: frameTimeout)
            try writer.start()
            return writer
        }
        var failures: [String] = []
        for config in Config.chain(width: width & ~1, height: height & ~1, bitRate: bitRate) {
            try Task.checkCancellation()
            let probeURL = url.deletingLastPathComponent().appendingPathComponent("probe-\(UUID().uuidString).mp4")
            let began = ContinuousClock.now
            var probe: ClipWriter?
            do {
                let writer = try ClipWriter(url: probeURL, config: config, timeout: probeTimeout)
                probe = writer
                try writer.start()
                for index in 0..<12 {
                    try await writer.appendFrame { context, size in
                        context.setFillColor(UIColor(hue: CGFloat(index) / 12, saturation: 0.5, brightness: 0.9,
                                                     alpha: 1).cgColor)
                        context.fill(CGRect(origin: .zero, size: size))
                        context.setFillColor(UIColor.white.cgColor)
                        context.fill(CGRect(x: CGFloat(index) * size.width / 12, y: 0, width: size.width / 6,
                                            height: size.height / 3))
                    }
                }
                try await writer.finish(totalFrames: 12)
                try? FileManager.default.removeItem(at: probeURL)
                log("probe ok \(config) in \(began.duration(to: .now))")
                chosen = config
                let real = try ClipWriter(url: url, config: config, timeout: frameTimeout)
                try real.start()
                return real
            } catch is CancellationError {
                probe?.cancel()
                throw CancellationError()
            } catch {
                probe?.cancel()
                log("probe failed \(config): \(error.localizedDescription) after \(began.duration(to: .now))")
                failures.append("\(config): \(error.localizedDescription)")
            }
        }
        throw WriterError.setup("no working encoder — " + failures.joined(separator: "; "))
    }

    private init(url: URL, config: Config, timeout: Duration) throws {
        self.url = url
        self.config = config
        self.timeout = timeout
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw WriterError.setup(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: config.bitRate,
            AVVideoExpectedSourceFrameRateKey: Int(Self.fps),
            AVVideoMaxKeyFrameIntervalKey: Int(Self.fps) * 2,
            AVVideoAllowFrameReorderingKey: config.allowReordering,
        ]
        if let profile = config.profile { compression[AVVideoProfileLevelKey] = profile }
        let settings: [String: Any] = [
            AVVideoCodecKey: config.codec,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw WriterError.setup("\(config) unsupported")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        // Offline render: the writer paces us; it never drops frames.
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: config.width,
            kCVPixelBufferHeightKey as String: config.height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw WriterError.setup("video track") }
        writer.add(input)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    private func start() throws {
        guard writer.startWriting() else {
            throw WriterError.setup(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)
        // Pull model: the writer calls us on our queue whenever it can take more; we hand over queued frames.
        input.requestMediaDataWhenReady(on: queue, using: Self.pullBlock(feed: feed, input: input, adaptor: adaptor))
        Self.log("start \(config)")
    }

    /// Built outside the main actor on purpose: it runs on the writer's queue and must not inherit main isolation.
    private nonisolated static func pullBlock(feed: FrameFeed, input: AVAssetWriterInput,
                                              adaptor: AVAssetWriterInputPixelBufferAdaptor) -> @Sendable () -> Void {
        {
            while input.isReadyForMoreMediaData {
                switch feed.take() {
                case .frame(let buffer, let time):
                    if !adaptor.append(buffer, withPresentationTime: time) {
                        feed.markFailed()
                        input.markAsFinished()
                        feed.markDone()
                        return
                    }
                    feed.markAppended()
                case .finish:
                    input.markAsFinished()
                    feed.markDone()
                    return
                case .abandon:
                    feed.markDone()
                    return
                }
            }
        }
    }

    // MARK: - Frames

    /// Draws the next frame (CoreGraphics, bottom-left origin; a bitmap context stores rows top-first, so
    /// `context.draw(cgImage, in: bounds)` comes out upright) and queues it for the encoder.
    func appendFrame(_ draw: (CGContext, CGSize) -> Void) async throws {
        try checkHealth()
        let buffer = try makeBuffer()
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: config.width,
            height: config.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        if let context {
            context.interpolationQuality = .high
            draw(context, CGSize(width: config.width, height: config.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard context != nil else { throw WriterError.encoding("bitmap context") }

        let time = CMTime(value: CMTimeValue(framesWritten), timescale: Self.fps)
        let deadline = ContinuousClock.now + timeout
        while !feed.offer(.frame(buffer, time)) {
            try Task.checkCancellation()
            try checkHealth()
            if ContinuousClock.now > deadline {
                Self.log("stalled at frame \(framesWritten) (\(feed.appendedCount) encoded) status=\(writer.status.rawValue)")
                throw WriterError.stalled
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        framesWritten += 1
        if framesWritten % 30 == 0 {
            Self.log("frame \(framesWritten) queued, \(feed.appendedCount) encoded, \(started.duration(to: .now))")
        }
    }

    /// Finishes the file; the clip ends exactly at `totalFrames` (the last frame keeps its full duration).
    func finish(totalFrames: Int) async throws {
        let deadline = ContinuousClock.now + timeout
        while !feed.offer(.finish) {
            try checkHealth()
            if ContinuousClock.now > deadline { throw WriterError.stalled }
            try await Task.sleep(for: .milliseconds(2))
        }
        while !feed.isDone {
            try checkHealth()
            if ContinuousClock.now > deadline {
                Self.log("stalled finishing (\(feed.appendedCount)/\(framesWritten) encoded)")
                throw WriterError.stalled
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        if feed.didFail { throw WriterError.encoding(writer.error?.localizedDescription ?? "append") }
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(max(totalFrames, framesWritten)), timescale: Self.fps))
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            writer.finishWriting { once.resume(true) }
            // finishWriting has hung on simulators; never wait on it forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { once.resume(false) }
        }
        guard finished else { throw WriterError.stalled }
        guard writer.status == .completed else {
            throw WriterError.encoding(writer.error?.localizedDescription ?? "finish")
        }
        Self.log("finished \(framesWritten) frames in \(started.duration(to: .now))")
    }

    /// Abandons the file (cancel or failure).
    func cancel() {
        feed.abandon()
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Internals

    private func checkHealth() throws {
        if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "failed") }
        if feed.didFail { throw WriterError.encoding(writer.error?.localizedDescription ?? "append") }
    }

    private func makeBuffer() throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let status: CVReturn
        if !config.ownBuffers, let pool = adaptor.pixelBufferPool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &created)
        } else {
            let attributes: [String: Any] = [
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
            ]
            status = CVPixelBufferCreate(kCFAllocatorDefault, config.width, config.height, kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &created)
        }
        guard status == kCVReturnSuccess, let buffer = created else {
            throw WriterError.encoding("pixel buffer \(status)")
        }
        return buffer
    }

    nonisolated static func log(_ message: String) {
        #if DEBUG
        print("SQUISH-T writer \(message)")
        #endif
    }
}

/// A tiny bounded queue between the main actor (producer) and the writer's queue (consumer).
/// The consumer blocks on a semaphore only on its own serial queue; the producer never blocks.
private final class FrameFeed: @unchecked Sendable {
    enum Item {
        case frame(CVPixelBuffer, CMTime)
        case finish
        case abandon
    }

    private let lock = NSLock()
    private let available = DispatchSemaphore(value: 0)
    private var items: [Item] = []
    private var closed = false
    private var done = false
    private var failed = false
    private var appended = 0
    private let capacity = 3

    /// Queues `item` if there is room (control items always fit). False = full, try again shortly.
    func offer(_ item: Item) -> Bool {
        lock.lock()
        if closed { lock.unlock(); return true }
        if case .frame = item, items.count >= capacity { lock.unlock(); return false }
        if case .frame = item {} else { closed = true }
        items.append(item)
        lock.unlock()
        available.signal()
        return true
    }

    /// Consumer side (writer queue): waits for the next item.
    func take() -> Item {
        lock.lock()
        let drained = items.isEmpty && closed
        lock.unlock()
        // Closed and empty: never block the writer's queue again.
        if drained { return .abandon }
        available.wait()
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty ? .abandon : items.removeFirst()
    }

    func abandon() {
        lock.lock()
        closed = true
        items.removeAll()
        items.append(.abandon)
        lock.unlock()
        available.signal()
    }

    func markAppended() { lock.lock(); appended += 1; lock.unlock() }
    func markFailed() { lock.lock(); failed = true; lock.unlock() }
    func markDone() { lock.lock(); done = true; lock.unlock() }

    var appendedCount: Int { lock.lock(); defer { lock.unlock() }; return appended }
    var didFail: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
}

/// Resumes a continuation exactly once, whichever of two racing callbacks comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// The clip's sound and the final lossless join.
enum ClipMuxer {
    enum MuxError: LocalizedError {
        case audio(String)
        case mux(String)

        var errorDescription: String? {
            switch self {
            case .audio(let detail): "Couldn't write the clip's sound (\(detail))."
            case .mux(let detail): "Couldn't join picture and sound (\(detail))."
            }
        }
    }

    /// Writes mono Float32 PCM as a 128 kbit/s AAC `.m4a` (AVAudioFile does the encoding; no interleaving involved).
    static func writeAudio(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            let chunk = 4096
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
                  let channel = buffer.floatChannelData?[0] else {
                throw MuxError.audio("PCM buffer")
            }
            var cursor = 0
            while cursor < samples.count {
                let count = min(chunk, samples.count - cursor)
                samples.withUnsafeBufferPointer { source in
                    guard let base = source.baseAddress else { return }
                    channel.update(from: base + cursor, count: count)
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                cursor += count
            }
        } catch let error as MuxError {
            throw error
        } catch {
            throw MuxError.audio(error.localizedDescription)
        }
        // `file` is closed when it goes out of scope above.
    }

    /// Joins the video and audio files into `output` without re-encoding (passthrough export).
    @MainActor static func mux(video: URL, audio: URL, to output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        do {
            guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
                  let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                throw MuxError.mux("missing track")
            }
            let videoRange = try await sourceVideo.load(.timeRange)
            let audioRange = try await sourceAudio.load(.timeRange)
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MuxError.mux("composition tracks")
            }
            try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
            let audioDuration = CMTimeMinimum(audioRange.duration, videoRange.duration)
            try audioTrack.insertTimeRange(CMTimeRange(start: audioRange.start, duration: audioDuration),
                                           of: sourceAudio, at: .zero)
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                throw MuxError.mux("export session")
            }
            session.shouldOptimizeForNetworkUse = true
            try await session.export(to: output, as: .mp4)
        } catch let error as MuxError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MuxError.mux(error.localizedDescription)
        }
    }
}
