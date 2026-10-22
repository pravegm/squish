import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Encodes the share clip (bible §10): H.264 High, 1080 × 1920, 30 fps, plus a mono 48 kHz AAC track,
/// into an MP4 with the movie header up front (plays while it uploads).
///
/// Frames are drawn with CoreGraphics straight into pooled BGRA pixel buffers. Audio is pre-rendered PCM, appended
/// in step with the video so the writer can interleave (it stalls one input if the other falls too far behind).
/// Main-actor bound: it is fed from the export loop, which already suspends between frames.
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
    static let audioChunk = 1024

    let url: URL
    let width: Int
    let height: Int
    private(set) var framesWritten = 0

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput
    private var audioFormat: CMAudioFormatDescription?
    private var audio: [Float] = []
    private var audioCursor = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(url: URL, width: Int = 1080, height: Int = 1920, videoBitRate: Int) throws {
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
            AVVideoExpectedSourceFrameRateKey: Int(ClipWriter.fps),
            AVVideoMaxKeyFrameIntervalKey: Int(ClipWriter.fps) * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let videoSettings: [String: Any] = [
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
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
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

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: OfflineAudio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { throw WriterError.setup("audio track") }
        writer.add(audioInput)

        var description = AudioStreamBasicDescription(
            mSampleRate: OfflineAudio.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
                                                    layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                    formatDescriptionOut: &format)
        guard status == noErr, let format else { throw WriterError.setup("audio format \(status)") }
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
        audioFormat = format
    }

    /// The whole clip's PCM (mono Float32, 48 kHz). Set before the first frame.
    func setAudio(_ samples: [Float]) {
        audio = samples
        audioCursor = 0
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
        try await waitUntilReady(videoInput)
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
            throw WriterError.encoding(writer.error?.localizedDescription ?? "append video")
        }
        framesWritten += 1
        // Keep the audio about half a second ahead of the video, never blocking on it.
        try appendAudio(upTo: Double(framesWritten) / Double(Self.fps) + 0.5)
    }

    /// Finishes both tracks; the clip ends exactly at `totalFrames`.
    func finish(totalFrames: Int) async throws {
        videoInput.markAsFinished()
        let end = Double(totalFrames) / Double(Self.fps)
        let deadline = ContinuousClock.now + .seconds(10)
        while audioCursor < min(audio.count, Int(end * OfflineAudio.sampleRate)) {
            try Task.checkCancellation()
            try appendAudio(upTo: end)
            if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "audio") }
            if ContinuousClock.now > deadline { throw WriterError.stalled }
            if !audioInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
        }
        audioInput.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(totalFrames), timescale: Self.fps))
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

    // MARK: - Internals

    private func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "failed") }
            if ContinuousClock.now > deadline { throw WriterError.stalled }
            // The writer may be waiting for audio to interleave with; feed it while we wait.
            try appendAudio(upTo: Double(framesWritten) / Double(Self.fps) + 1.0)
            try await Task.sleep(for: .milliseconds(4))
        }
        if writer.status == .failed { throw WriterError.encoding(writer.error?.localizedDescription ?? "failed") }
    }

    /// Appends PCM chunks up to `seconds` while the audio input accepts them.
    private func appendAudio(upTo seconds: Double) throws {
        guard let audioFormat else { return }
        let target = min(audio.count, Int(seconds * OfflineAudio.sampleRate))
        while audioCursor < target, audioInput.isReadyForMoreMediaData {
            let count = min(Self.audioChunk, target - audioCursor)
            guard let buffer = makeAudioBuffer(from: audioCursor, count: count, format: audioFormat) else {
                throw WriterError.encoding("audio buffer")
            }
            guard audioInput.append(buffer) else {
                throw WriterError.encoding(writer.error?.localizedDescription ?? "append audio")
            }
            audioCursor += count
        }
    }

    private func makeAudioBuffer(from start: Int, count: Int, format: CMAudioFormatDescription) -> CMSampleBuffer? {
        let bytes = count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                        blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                                        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == kCMBlockBufferNoErr, let block else { return nil }
        status = audio.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base + start * MemoryLayout<Float>.size, blockBuffer: block,
                                                 offsetIntoDestination: 0, dataLength: bytes)
        }
        guard status == kCMBlockBufferNoErr else { return nil }
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(OfflineAudio.sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else { return nil }
        return sampleBuffer
    }
}
