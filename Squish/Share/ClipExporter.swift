import Foundation
import UIKit

/// Renders the 9:16 share clip of one press (bible §10): 1080 × 1920, 30 fps, 6–10 s with sound, under 8 MB.
/// Re-rendered offline from the stored input trace plus seed, never screen-recorded.
///
/// Pipeline:
/// 1. **Analyse.** Replay the trace through a private `PressEngine` at a fine fixed step; build a `ClipTimeline` that
///    speeds up dull stretches, plays the failure at 0.3×, and fits title + press + end card into 6–10 s.
/// 2. **Audio.** Replay again along the timeline's exact drive steps into `OfflineAudio` (the live controller's
///    contract, writing a score instead of playing), then render the score through a private `Synth` off the main actor.
/// 3. **Video.** Replay a third time, with the same drive steps, into a fresh `PressScene` hosted on screen in the
///    temporary `ClipStudio` window, exactly as the director drives it (engine step → events → `scene.handle`,
///    then `scene.update`). After each frame's step: wait for RealityKit to render, snapshot, encode.
///    Title and end cards are SwiftUI compositions rendered with `ImageRenderer`.
/// 4. **Mux.** `ClipWriter` encodes H.264 picture only; `ClipMuxer` writes the sound as AAC with AVAudioFile and joins
///    both with a passthrough export (no re-encode) into tmp/SquishClips. No single writer has to interleave two inputs.
///
/// The engine is deterministic for identical inputs and step times, so the audio and video passes see the same
/// events on the same frames.
@MainActor
final class ClipExporter {
    enum ExportError: LocalizedError {
        case emptyTrace
        case noScreen
        case snapshotFailed
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .emptyTrace: "This press wasn't recorded, so there's nothing to replay."
            case .noScreen: "The clip can only render while Squish is on screen."
            case .snapshotFailed: "The press scene didn't render. Try again in a moment."
            case .writer(let detail): "The clip couldn't be encoded: \(detail)"
            }
        }
    }

    static let width = 1080
    static let height = 1920
    /// Bible §10: under 8 MB. 4.4 Mbit/s video + 128 kbit/s audio is ≈ 5.7 MB at the 10 s maximum.
    static let videoBitRate = 4_400_000
    /// Frames of crossfade from the last press frame into the end card.
    static let endCrossfade = 8

    private var work: Task<URL, Error>?

    init() {}

    func export(trace: PressTrace, specimen: SpecimenRecord, progress: @escaping (Double) -> Void) async throws -> URL {
        let work = Task { @MainActor in
            try await self.render(trace: trace, specimen: specimen, progress: progress)
        }
        self.work = work
        defer { self.work = nil }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    // MARK: - Pipeline

    private func render(trace: PressTrace, specimen: SpecimenRecord, progress: @escaping (Double) -> Void) async throws -> URL {
        guard !trace.samples.isEmpty else { throw ExportError.emptyTrace }
        progress(0)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        // The user's sound style (Soft = misophonia-safe) carries into the clip; the clip always has sound.
        let style = AppSettings().soundStyle

        // 1. Analyse and retime.
        let analysis = PressReplay.analyse(trace)
        let timeline = ClipTimeline.make(from: analysis)
        let steps = timeline.driveSteps()
        try Task.checkCancellation()
        progress(0.02)

        let files = try Self.workFiles(for: specimen)
        var finished = false
        defer {
            try? FileManager.default.removeItem(at: files.work)
            if !finished { try? FileManager.default.removeItem(at: files.output) }
        }

        // 2. Audio: score on the main actor (engine + cue book), synthesis and AAC encoding off it.
        //    A sound failure degrades to a silent clip rather than no clip.
        let score = Self.score(trace: trace, timeline: timeline, steps: steps, style: style, reduceMotion: reduceMotion)
        let totalSamples = timeline.totalFrames * Int(OfflineAudio.sampleRate) / ClipTimeline.fps
        let audioURL = files.audio
        let audioWritten = await Task.detached(priority: .userInitiated) { () -> Bool in
            let pcm = OfflineAudio.render(score, frames: totalSamples)
            do {
                try ClipMuxer.writeAudio(pcm, sampleRate: OfflineAudio.sampleRate, to: audioURL)
                return true
            } catch {
                print("SQUISH-CLIP audio skipped: \(error.localizedDescription)")
                return false
            }
        }.value
        try Task.checkCancellation()
        progress(0.06)

        // 3. Picture: writer and studio.
        let writer: ClipWriter
        do {
            writer = try ClipWriter(url: files.video, width: Self.width, height: Self.height, videoBitRate: Self.videoBitRate)
            try writer.start()
        } catch {
            throw ExportError.writer(error.localizedDescription)
        }
        let studio: ClipStudio
        do {
            studio = try ClipStudio(onCancel: { [weak self] in self?.work?.cancel() })
        } catch {
            writer.cancel()
            throw error
        }
        defer { studio.close() }

        let report: (Double) -> Void = { value in
            studio.model.progress = value
            progress(value)
        }

        do {
            try await renderFrames(trace: trace, specimen: specimen, timeline: timeline, steps: steps, style: style,
                                   reduceMotion: reduceMotion, studio: studio, writer: writer, report: report)
            studio.model.stage = "Developing…"
            try await writer.finish(totalFrames: timeline.totalFrames)
            try Task.checkCancellation()
            // 4. Join picture and sound losslessly; without sound, the picture alone is the clip.
            if audioWritten {
                do {
                    try await ClipMuxer.mux(video: files.video, audio: files.audio, to: files.output)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    print("SQUISH-CLIP mux failed, sharing picture only: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: files.output)
                    try FileManager.default.moveItem(at: files.video, to: files.output)
                }
            } else {
                try FileManager.default.moveItem(at: files.video, to: files.output)
            }
        } catch {
            writer.cancel()
            if error is CancellationError { throw error }
            if let known = error as? ExportError { throw known }
            throw ExportError.writer(error.localizedDescription)
        }
        finished = true
        report(1)
        return files.output
    }

    private func renderFrames(trace: PressTrace, specimen: SpecimenRecord, timeline: ClipTimeline,
                              steps: [ClipTimeline.DriveStep], style: SoundStyle, reduceMotion: Bool,
                              studio: ClipStudio, writer: ClipWriter, report: (Double) -> Void) async throws {
        let width = CGFloat(Self.width)
        let height = CGFloat(Self.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let backdrop = UIColor(Theme.gel(for: specimen.kind, golden: specimen.variant.isGolden)).cgColor
        let totalFrames = Double(max(timeline.totalFrames, 1))

        // Set the scene up first, so its studio light, sweep and object build while the title card encodes.
        let scene = studio.scene
        scene.isFirstPress = false
        let replay = PressReplay(trace: trace)
        let engine = replay.engine
        let feedback = { () -> FeedbackContext in
            FeedbackContext(kind: trace.kind, variant: trace.variant, compression: Float(engine.measuredCompression),
                            closingSpeed: Float(engine.closingSpeed), soundStyle: style, reduceMotion: reduceMotion)
        }
        replay.onEvent = { event, _ in
            scene.handle(event, context: feedback())
        }
        replay.load()
        scene.setObject(trace.kind, variant: trace.variant)
        scene.update(engine: engine, context: feedback(), dt: 0)

        // Title card, with a slow 4 % push-in. Degrades to the plain gel colour if it can't be drawn.
        studio.model.stage = "Setting the stage…"
        let title = ClipCards.title(for: specimen)
        for frame in 0..<timeline.titleFrames {
            try Task.checkCancellation()
            let t = Double(frame) / Double(max(timeline.titleFrames - 1, 1))
            try await writer.appendFrame { context, _ in
                context.setFillColor(backdrop)
                context.fill(bounds)
                if let title {
                    Self.draw(title, in: context, bounds: bounds, zoom: 1 + 0.04 * t)
                }
            }
            report(0.06 + 0.04 * Double(writer.framesWritten) / totalFrames)
        }

        // Studio ready, then stage the object: the first object's power-on beat and drop play on scene time, so run
        // them (engine idle at source 0) until it has landed — off camera, no frames captured.
        try await studio.warmUp(engine: engine, context: feedback())
        let staging = max(0, Self.stagingTime - timeline.sourceStart)
        for _ in 0..<Int((staging * 20).rounded(.up)) {
            scene.update(engine: engine, context: feedback(), dt: 1.0 / 20)
        }

        // The press, re-rendered: one engine/scene step per drive step; capture on frame steps.
        studio.model.stage = "Re-pressing it frame by frame…"
        var lastFrame: CGImage?
        var misses = 0
        for step in steps {
            try Task.checkCancellation()
            let dt = max(step.source - replay.clock, 0)
            replay.advance(to: step.source)
            scene.update(engine: engine, context: feedback(), dt: Float(dt))
            guard step.frame != nil else { continue }

            if let image = await studio.captureFrame()?.cgImage {
                lastFrame = image
                misses = 0
            } else {
                misses += 1
                // A dropped snapshot repeats the previous frame; a renderer that never draws is an error.
                if lastFrame == nil || misses > 12 { throw ExportError.snapshotFailed }
            }
            guard let frame = lastFrame else { throw ExportError.snapshotFailed }
            try await writer.appendFrame { context, _ in
                context.setFillColor(backdrop)
                context.fill(bounds)
                Self.draw(frame, in: context, bounds: bounds, zoom: 1)
            }
            report(0.10 + 0.84 * Double(writer.framesWritten) / totalFrames)
        }

        // End card: the scene's clean top-down specimen shot (FOLD-PRESS §9.6), else a crop of the last frame;
        // crossfade in from the final press frame, then a gentle push-in.
        studio.model.stage = "Pressing the specimen card…"
        var still = await scene.specimenSnapshot()
        if still == nil { still = lastFrame.flatMap(ClipCards.specimenCrop(of:)) }
        let end = ClipCards.end(for: specimen, still: still)
        for frame in 0..<timeline.endFrames {
            try Task.checkCancellation()
            let t = Double(frame) / Double(max(timeline.endFrames - 1, 1))
            let fade = min(Double(frame + 1) / Double(Self.endCrossfade), 1)
            try await writer.appendFrame { context, _ in
                context.setFillColor(backdrop)
                context.fill(bounds)
                if let lastFrame, fade < 1 {
                    Self.draw(lastFrame, in: context, bounds: bounds, zoom: 1)
                }
                if let end {
                    context.setAlpha(CGFloat(fade))
                    Self.draw(end, in: context, bounds: bounds, zoom: 1 + 0.03 * t)
                    context.setAlpha(1)
                }
            }
            report(0.94 + 0.04 * Double(frame + 1) / Double(max(timeline.endFrames, 1)))
        }
    }

    /// Scene seconds from placement until a first object has powered on, dropped and settled (PressScene: drop at
    /// 0.8 s after the studio is ready, ~0.3 s fall, ~0.35 s squash).
    static let stagingTime = 1.7

    /// Draws `image` aspect-filled into `bounds`, scaled about the centre by `zoom`.
    nonisolated private static func draw(_ image: CGImage, in context: CGContext, bounds: CGRect, zoom: CGFloat) {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let fill = max(bounds.width / imageSize.width, bounds.height / imageSize.height) * zoom
        let size = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        context.draw(image, in: rect)
    }

    // MARK: - Audio score

    /// Replays the press along the drive steps into the offline audio controller, as the director would drive the
    /// live one: `place` after the load, `handle` for every event, `update` once per step.
    private static func score(trace: PressTrace, timeline: ClipTimeline, steps: [ClipTimeline.DriveStep],
                              style: SoundStyle, reduceMotion: Bool) -> OfflineAudio.Score {
        let audio = OfflineAudio(style: style)
        let replay = PressReplay(trace: trace)
        let engine = replay.engine
        let context = { () -> FeedbackContext in
            FeedbackContext(kind: trace.kind, variant: trace.variant, compression: Float(engine.measuredCompression),
                            closingSpeed: Float(engine.closingSpeed), soundStyle: style, reduceMotion: reduceMotion)
        }
        func seek(_ source: Double) {
            audio.seek(to: timeline.clipTime(atSource: source) ?? -1, rate: timeline.playbackRate(atSource: source))
        }
        replay.onEvent = { event, time in
            seek(time)
            audio.handle(event, context: context())
        }
        replay.load()
        seek(0)
        audio.place(context: context())

        // Title card: the ka-chunk's two "ready" tinks, the brand's quiet hello.
        audio.seek(to: 0.18, rate: 1)
        audio.play(OfflineAudio.readyTinks)

        for step in steps {
            let dt = max(step.source - replay.clock, 0)
            replay.advance(to: step.source)
            seek(step.source)
            audio.update(engine: engine, context: context(), dt: dt)
        }

        // End card: the collect answer to the reveal sting.
        audio.seek(to: timeline.endStart + 0.3, rate: 1)
        audio.play(BrandCues.collect)
        return audio.score
    }

    // MARK: - Files

    struct WorkFiles {
        var work: URL
        var video: URL
        var audio: URL
        var output: URL
    }

    /// tmp/SquishClips/Squish-Rubber-Duck-0042.mp4 (+ a work folder for the picture and sound before the join).
    /// Earlier clips are cleared first, so only one is ever kept.
    private static func workFiles(for specimen: SpecimenRecord) throws -> WorkFiles {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SquishClips", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let work = directory.appendingPathComponent("work", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            throw ExportError.writer("no space for a temporary file")
        }
        let name = "Squish-\(specimen.kind.displayName.replacingOccurrences(of: " ", with: "-"))-\(String(format: "%04ld", specimen.number)).mp4"
        return WorkFiles(work: work, video: work.appendingPathComponent("video.mp4"),
                         audio: work.appendingPathComponent("audio.m4a"), output: directory.appendingPathComponent(name))
    }
}