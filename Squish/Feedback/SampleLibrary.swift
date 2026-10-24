import AVFoundation
import Foundation
import os

/// The recorded foley library (EXPERIENCE-PLAN: "Recorded foley is the core of the sound"), cut by the sound
/// designer's pipeline (`ci/sounds/`) into `Squish/Resources/Sounds/` with `sounds-manifest.json`.
///
/// Loaded once, off the main thread, at launch (`loadInBackground`). Every file is decoded to mono Float32 and kept
/// for the life of the app (≈ 2× the 16-bit bundle size), so the audio thread plays straight from memory: a
/// `.sample` synth voice reads `SampleData` with no locks, no ARC and no file I/O.
///
/// UI groups are skipped (UI sounds belong to the UI). Loops are kept for the recorded strain beds.
final class SampleLibrary: @unchecked Sendable {
    /// One file: its PCM and the haptic transients measured from its audio onsets (SOUND-2 §4.1: the sample is the
    /// score), as (time s, intensity 0…1, sharpness 0…1).
    struct File: Sendable {
        let data: SampleData
        let onsets: [HapticOnset]
    }

    struct HapticOnset: Sendable, Equatable {
        let time: Double
        let intensity: Float
        let sharpness: Float
    }

    struct Group: Sendable {
        let name: String
        let files: [File]
        /// The manifest class: grain, detail, body, hero, tail or loop (it decides the haptic treatment).
        let role: String
        /// Bus trim from the manifest.
        let gainDb: Float
        /// Random pitch spread per play, ± semitones.
        let pitch: Float
        /// Liquid layers: the Soft style keeps the synthesised version instead.
        let wet: Bool
    }

    let groups: [String: Group]
    let fileCount: Int
    let loadSeconds: Double
    let problem: String?

    private init(groups: [String: Group], fileCount: Int, loadSeconds: Double, problem: String?) {
        self.groups = groups
        self.fileCount = fileCount
        self.loadSeconds = loadSeconds
        self.problem = problem
    }

    // MARK: Loading

    private static let instance = SampleLibrary.load(bundle: .main)
    private static let ready = OSAllocatedUnfairLock(initialState: false)
    private static let started = OSAllocatedUnfairLock(initialState: false)

    /// The library once it has loaded, nil before (the synth layers play meanwhile). Never blocks.
    static var loaded: SampleLibrary? {
        ready.withLock { $0 } ? instance : nil
    }

    /// Starts loading on a background queue (once). Call at launch.
    static func loadInBackground() {
        let first = started.withLock { state -> Bool in
            defer { state = true }
            return !state
        }
        guard first else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = instance
            ready.withLock { $0 = true }
        }
    }

    /// The library, loading it now on this thread if needed (offline renders and tests, which must be repeatable).
    static func loadNow() -> SampleLibrary {
        let library = instance
        ready.withLock { $0 = true }
        return library
    }

    private struct Manifest: Decodable {
        struct File: Decodable {
            var name: String
            var haptics: [[Double]]?
        }

        struct Entry: Decodable {
            var files: [File]
            var kind: String
            var gainDb: Double
            var pitch: Double
            var wet: Bool
        }

        var groups: [String: Entry]
    }

    private static func load(bundle: Bundle) -> SampleLibrary {
        let start = CFAbsoluteTimeGetCurrent()
        guard let url = bundle.url(forResource: "sounds-manifest", withExtension: "json") else {
            return SampleLibrary(groups: [:], fileCount: 0, loadSeconds: 0, problem: "No sounds-manifest.json in the app")
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        } catch {
            return SampleLibrary(groups: [:], fileCount: 0, loadSeconds: 0,
                                 problem: "Couldn't read sounds-manifest.json: \(error.localizedDescription)")
        }
        var groups: [String: Group] = [:]
        var count = 0
        var missing = 0
        for (name, entry) in manifest.groups where entry.kind != "ui" {
            var files: [File] = []
            for file in entry.files {
                if let data = decode(file.name, bundle: bundle) {
                    let onsets = (file.haptics ?? []).compactMap { row -> HapticOnset? in
                        guard row.count >= 3 else { return nil }
                        return HapticOnset(time: max(row[0], 0), intensity: Float(min(max(row[1], 0), 1)),
                                           sharpness: Float(min(max(row[2], 0), 1)))
                    }
                    files.append(File(data: data, onsets: onsets))
                } else {
                    missing += 1
                }
            }
            guard !files.isEmpty else { continue }
            count += files.count
            groups[name] = Group(name: name, files: files, role: entry.kind, gainDb: Float(entry.gainDb),
                                 pitch: Float(entry.pitch), wet: entry.wet)
        }
        return SampleLibrary(groups: groups, fileCount: count, loadSeconds: CFAbsoluteTimeGetCurrent() - start,
                             problem: missing > 0 ? "\(missing) files listed but missing" : nil)
    }

    /// One CAF → mono Float32 in memory that is never freed (the library lives as long as the app).
    private static func decode(_ name: String, bundle: Bundle) -> SampleData? {
        guard let url = bundle.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url),
              file.length > 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 1 else { return nil }
        let frames = Int(buffer.frameLength)
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        storage.initialize(from: channel, count: frames)
        return SampleData(samples: UnsafePointer(storage), count: frames, sampleRate: Float(file.processingFormat.sampleRate))
    }
}

