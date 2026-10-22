import AVFoundation
import Foundation
import Testing
import UIKit
@testable import Squish

/// Share clip (bible §10): deterministic replay, retiming into 6–10 s with the failure at 0.3×,
/// offline audio, cards and the encoder.
@MainActor
struct ShareTests {
    /// A touch press: `lead` seconds on the anvil, then a steady close from 180° to 30° over `seconds`.
    private func touchTrace(_ kind: ObjectKind, seconds: Double = 3, lead: Double = 1, seed: UInt64 = 42,
                            holdAtHalfway: Double = 0) -> PressTrace {
        let rate = 60.0
        var samples: [PressTrace.Sample] = []
        var time = lead
        let steps = max(Int(seconds * rate), 1)
        for i in 0...steps {
            let angle = 180 - 150 * Double(i) / Double(steps)
            samples.append(PressTrace.Sample(time: time, angle: angle, closed: false))
            time += 1 / rate
            if i == steps / 2 && holdAtHalfway > 0 {
                for _ in 0..<Int(holdAtHalfway * rate) {
                    samples.append(PressTrace.Sample(time: time, angle: angle, closed: false))
                    time += 1 / rate
                }
            }
        }
        return PressTrace(kind: kind, variant: PressVariant(kind: kind, seed: seed), samples: samples,
                          usesVirtualHinge: true, config: .standard)
    }

    // MARK: Replay

    @Test func replayIsDeterministicAndFindsTheFailure() {
        let trace = touchTrace(.rubberDuck)
        let first = PressReplay.analyse(trace)
        let second = PressReplay.analyse(trace)
        #expect(first == second)
        #expect(first.failureTime != nil)
        #expect(first.revealTime != nil)
        if let failure = first.failureTime, let reveal = first.revealTime {
            #expect(failure < reveal)
        }
    }

    // MARK: Timeline

    @Test(arguments: [0.4, 3.0, 9.0])
    func clipLengthStaysInsideTheBibleWindow(seconds: Double) {
        let analysis = PressReplay.analyse(touchTrace(.rubberDuck, seconds: seconds))
        let timeline = ClipTimeline.make(from: analysis)
        #expect(timeline.totalDuration >= 6 && timeline.totalDuration <= 10, "got \(timeline.totalDuration) s")
        #expect(timeline.titleDuration == 1)
    }

    @Test func longDullHoldIsSpedUp() {
        let analysis = PressReplay.analyse(touchTrace(.glassBottle, seconds: 4, lead: 12, holdAtHalfway: 25))
        let timeline = ClipTimeline.make(from: analysis)
        #expect(timeline.totalDuration <= 10)
        #expect(timeline.sourceEnd - timeline.sourceStart > timeline.pressDuration * 2)
    }

    @Test func failurePlaysAtThirtyPercent() throws {
        let analysis = PressReplay.analyse(touchTrace(.rubberDuck))
        let failure = try #require(analysis.failureTime)
        let timeline = ClipTimeline.make(from: analysis)
        #expect(abs(timeline.playbackRate(atSource: failure) - ClipTimeline.failureSlowMo) < 0.02)
        #expect(abs(timeline.playbackRate(atSource: failure + 0.3) - ClipTimeline.failureSlowMo) < 0.02)
    }

    @Test func timeMappingRoundTrips() throws {
        let timeline = ClipTimeline.make(from: PressReplay.analyse(touchTrace(.egg)))
        for f in stride(from: 0.0, through: 1.0, by: 0.05) {
            let source = timeline.sourceStart + (timeline.sourceEnd - timeline.sourceStart) * f
            let clip = try #require(timeline.clipTime(atSource: source))
            #expect(abs(timeline.source(atPressTime: clip - timeline.titleDuration) - source) < 1e-6)
        }
        #expect(timeline.clipTime(atSource: timeline.sourceStart - 1) == nil)
    }

    @Test func driveStepsCaptureEveryFrameInOrder() {
        let timeline = ClipTimeline.make(from: PressReplay.analyse(touchTrace(.sodaCan)))
        let steps = timeline.driveSteps()
        #expect(steps.compactMap(\.frame) == Array(0..<timeline.pressFrames))
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.source <= $1.source })
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $1.source - $0.source <= 1.0 / 20 + 1e-9 })
    }

    // MARK: Audio

    private func renderAudio(_ trace: PressTrace) -> [Float] {
        let timeline = ClipTimeline.make(from: PressReplay.analyse(trace))
        let audio = OfflineAudio(style: .workshop)
        let replay = PressReplay(trace: trace)
        let engine = replay.engine
        let context = {
            FeedbackContext(kind: trace.kind, variant: trace.variant, compression: Float(engine.measuredCompression),
                            closingSpeed: Float(engine.closingSpeed), soundStyle: .workshop, reduceMotion: false)
        }
        replay.onEvent = { event, time in
            audio.seek(to: timeline.clipTime(atSource: time) ?? -1, rate: timeline.playbackRate(atSource: time))
            audio.handle(event, context: context())
        }
        replay.load()
        audio.seek(to: timeline.clipTime(atSource: 0) ?? -1, rate: 1)
        audio.place(context: context())
        for step in timeline.driveSteps() {
            let dt = step.source - replay.clock
            replay.advance(to: step.source)
            audio.seek(to: timeline.clipTime(atSource: step.source) ?? -1, rate: timeline.playbackRate(atSource: step.source))
            audio.update(engine: engine, context: context(), dt: dt)
        }
        return OfflineAudio.render(audio.score, frames: timeline.totalFrames * 1600)
    }

    @Test func offlineAudioIsAudibleBoundedAndRepeatable() {
        let trace = touchTrace(.rubberDuck)
        let first = renderAudio(trace)
        let allFinite = first.allSatisfy { $0.isFinite }
        #expect(allFinite)
        let peak = first.map { abs($0) }.max() ?? 0
        #expect(peak > 0.01)
        #expect(peak <= 0.9)
        #expect(first == renderAudio(trace))
    }

    @Test func slowMotionLowersPitchAndStretchesEnvelopes() {
        let tone = SynthCommand.tone(ToneSpec(start: 1000, end: 500, glide: 0.1, duration: 0.2, attack: 0.01, decay: 0.05,
                                              gain: 0.3, harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: 0))
        guard case let .tone(slowed) = OfflineAudio.retimed(tone, pitch: 0.8) else {
            Issue.record("expected a tone")
            return
        }
        #expect(abs(slowed.start - 800) < 0.01)
        #expect(abs(slowed.duration - 0.25) < 0.001)
        #expect(slowed.gain == 0.3)
        #expect(OfflineAudio.retimed(tone, pitch: 1) == tone)
    }

    // MARK: Cards and encoder

    @Test func cardsRenderAtClipResolution() throws {
        let specimen = SpecimenRecord(id: UUID(), number: 42, kind: .rubberDuck, date: Date(),
                                      variant: PressVariant(kind: .rubberDuck, seed: 7), fractureCount: 2,
                                      maxCompression: 0.9, failureAngle: 88, duration: 3.2, isPerfect: true,
                                      wasSlammed: false)
        let title = try #require(ClipCards.title(for: specimen))
        #expect(title.width == 1080 && title.height == 1920)
        let end = try #require(ClipCards.end(for: specimen, still: nil))
        #expect(end.width == 1080 && end.height == 1920)
    }

    @Test func writerAndMuxerProduceAnMP4WithVideoAndAudio() async throws {
        // The queue-driven writer with codec probing passes on the CI simulator (run 39820908508), but the simulator's
        // hardware encoder sometimes stops responding for a whole run (39843634884). Only that failure is tolerated;
        // CI scenario 80 still renders a real clip end to end.
        await withKnownIssue("CI simulator video encoder unavailable", isIntermittent: true) {
            try await writerScenario()
        } matching: { issue in
            issue.error.map { String(describing: $0).contains("stopped responding") } ?? false
        }
    }

    private func writerScenario() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShareTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("video.mp4")
        let audio = directory.appendingPathComponent("audio.m4a")
        let output = directory.appendingPathComponent("clip.mp4")

        // Picture: 1 s at the clip's own resolution and bitrate, through the same probed fallback chain as the export.
        let writer = try await ClipWriter.make(url: video, width: ClipExporter.width, height: ClipExporter.height,
                                               bitRate: ClipExporter.videoBitRate)
        #expect(writer.width % 2 == 0 && writer.height % 2 == 0)
        #expect(writer.width * 16 == writer.height * 9)
        for i in 0..<30 {
            try await writer.appendFrame { context, size in
                context.setFillColor(UIColor(hue: CGFloat(i) / 30, saturation: 0.6, brightness: 0.9, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        try await writer.finish(totalFrames: 30)
        #expect(writer.framesWritten == 30)

        // Sound: 1 s of A4 through AVAudioFile's AAC encoder.
        let omega = 2 * Double.pi * 440 / OfflineAudio.sampleRate
        let pcm = (0..<Int(OfflineAudio.sampleRate)).map { index -> Float in Float(0.2 * sin(Double(index) * omega)) }
        try ClipMuxer.writeAudio(pcm, sampleRate: OfflineAudio.sampleRate, to: audio)

        try await ClipMuxer.mux(video: video, audio: audio, to: output)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        #expect(((attributes[.size] as? NSNumber)?.intValue ?? 0) > 1000)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1) < 0.1)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(videoTracks.count == 1)
        #expect(audioTracks.count == 1)
    }
}