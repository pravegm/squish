// Re-times a `simctl io recordVideo` file for ffmpeg: decodes it with AVFoundation (frames in presentation order, at
// their true presentation times) and re-encodes it as H.264 with no frame reordering, so dts = pts for every frame.
//
// Why: recordVideo files carry a few samples with huge composition offsets (ctts ±1.2 s in preview run 39979175998's
// glass take, ±8.4 s in run 39965173658's duck). ffmpeg's best-effort timestamps then switch partway through to a dts
// timeline shifted by that offset, so cuts landed 1–5 s from the asked time, while the same files played back in a
// browser (true pts) matched the app's wall-clock marks frame for frame.
//
// Usage: xcrun swift ci/preview-retime.swift <in.mp4> <out.mp4>   (prints one summary line; exit 1 on failure)
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: preview-retime <in.mp4> <out.mp4>")
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
try? FileManager.default.removeItem(at: outputURL)

let asset = AVURLAsset(url: inputURL)
guard let track = asset.tracks(withMediaType: .video).first else {
    print("retime failed: no video track in \(inputURL.lastPathComponent)")
    exit(1)
}
let size = track.naturalSize

do {
    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    readerOutput.alwaysCopiesSampleData = false
    reader.add(readerOutput)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let compression: [String: Any] = [
        AVVideoAverageBitRateKey: 40_000_000,
        AVVideoAllowFrameReorderingKey: false,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 30,
    ]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height),
        AVVideoCompressionPropertiesKey: compression,
    ])
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)

    guard reader.startReading() else {
        print("retime failed: reader: \(reader.error?.localizedDescription ?? "unknown")")
        exit(1)
    }
    guard writer.startWriting() else {
        print("retime failed: writer: \(writer.error?.localizedDescription ?? "unknown")")
        exit(1)
    }
    writer.startSession(atSourceTime: .zero)

    var last = CMTime.negativeInfinity
    var written = 0
    var dropped = 0
    var first = -1.0
    while let sample = readerOutput.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time.isValid, CMTimeCompare(time, last) > 0 else {
            dropped += 1
            continue
        }
        while !writerInput.isReadyForMoreMediaData { usleep(2_000) }
        guard writerInput.append(sample) else {
            print("retime failed: append at \(time.seconds) s: \(writer.error?.localizedDescription ?? "unknown")")
            exit(1)
        }
        if first < 0 { first = time.seconds }
        last = time
        written += 1
    }
    if reader.status == .failed {
        print("retime failed: reading: \(reader.error?.localizedDescription ?? "unknown")")
        exit(1)
    }
    writerInput.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else {
        print("retime failed: finishing: \(writer.error?.localizedDescription ?? "unknown")")
        exit(1)
    }
    print(String(format: "retimed %@: %ld frames, %ld out of order dropped, %.0fx%.0f, first %.3f s, last %.3f s",
                 inputURL.lastPathComponent, written, dropped, Double(size.width), Double(size.height), first,
                 last.seconds))
} catch {
    print("retime failed: \(error.localizedDescription)")
    exit(1)
}
