import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Encodes the share clip's picture (bible §10): H.264 High, 1080 × 1920, 30 fps, into a video-only MP4.
///
/// Video only on purpose: one AVAssetWriter fed both H.264 frames and AAC audio from a polling loop stalled in CI
/// (the writer withholds `isReadyForMoreMediaData` from one input while it waits to interleave the other). The sound
/// is written separately by `ClipMuxer.writeAudio` and joined losslessly by `ClipMuxer.mux`, so nothing here can
/// starve. Frames are drawn with CoreGraphics straight into pooled BGRA pixel buffers.
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

    static let fps: Int32 = 30

    let url: URL
    let width: Int
    let height: Int
    private(set) var framesWritten = 0

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(url: URL, width: Int = 1080, height: Int = 1920, videoBitRate: Int) throws {
        // H.264 needs even dimensions.
        let width = width & ~1
        let height = height & ~1
        self.url = url
        self.width = width
        self.height = height
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw WriterError.setup(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitRate,
            AVVideoExpectedSourceFrameRateKey: Int(Self.fps),
            AVVideoMaxKeyFrameIntervalKey: Int(Self.fps) * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw WriterError.setup("H.264 \(width)×\(height) unsupported")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        // Offline render: the writer may hold us back (we wait), it never drops frames.
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ])
        guard writer.canAdd(videoInput) else { throw WriterError.setup("video track") }
        writer.add(videoInput)
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
    }

    func start() throws {
        guard writer.startWriting() else {
            throw WriterError.setup(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// Draws the next frame and appends it. The context is plain CoreGraphics (bottom-left origin); a bitmap
    /// context stores rows top-first, so `context.draw(cgImage, in: bounds)` comes out upright.
    func appendFrame(_ draw: (CGContext, CGSize) -> Void) async throws {
        try await waitUntilReady()
        guard let pool = adaptor.pixelBufferPool else { throw WriterError.encoding("no pixel buffer pool") }
        var created: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &created)
        guard status == kCVReturnSuccess, let buffer = created else {
            throw WriterError.encoding("pixel buffer \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        if let context {
            context.interpolationQuality = .high
            draw(context, CGSize(width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard context != nil else { throw WriterError.encoding("bitmap context") }

        let time = CMTime(value: CMTimeValue(framesWritten), timescale: Self.fps)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw WriterError.encoding(writer.error?.localizedDescription ?? "append")
        }
        framesWritten += 1
    }

    /// Finishes the file; the clip ends exactly at `totalFrames` (the last frame keeps its full duration).
    func finish(totalFrames: Int) async throws {
        videoInput.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(max(totalFrames, framesWritten)), timescale: Self.fps))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw WriterError.encoding(writer.error?.localizedDescription ?? "finish")
        }
    }

    /// Abandons the file (cancel or failure).
    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    private func waitUntilReady() async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !videoInput.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "failed") }
            if ContinuousClock.now > deadline { throw WriterError.stalled }
            try await Task.sleep(for: .milliseconds(2))
        }
        if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "failed") }
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
