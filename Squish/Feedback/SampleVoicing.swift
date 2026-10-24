import Foundation

/// Which moments the recorded foley voices, by slot key ("<object or press>.<event>"), and how (design/SOUND-2.md §1.2,
/// §4.2, §5.1). Synthesis stays for the creak, ticks, hiss shaping, hum, low-end bodies, modal rings, the hush and the
/// brand stings; the recordings take over the noise bodies, pops, squeaks, cracks and crunches.
enum SampleMap {
    enum Mode: Equatable {
        /// Drop the synth layers the recording competes with (noise and crunch bodies, tones from 300 Hz up: pops,
        /// squeaks) and keep the rest (thumps and sub tones below 300 Hz, modal rings).
        case replace
        /// Add the recording under everything (the ka-chunk's latch and metal, the contact, the stamp).
        case layer
        /// Replace exactly these layers of the event.
        case only(Set<String>)
    }

    struct Pick: Equatable {
        var group: String
        var delay: Float = 0
        var gain: Float = 1
    }

    struct Rule: Equatable {
        var picks: [Pick]
        var mode: Mode = .replace
    }

    private static func rule(_ groups: String..., mode: Mode = .replace) -> Rule {
        Rule(picks: groups.map { Pick(group: $0) }, mode: mode)
    }

    static func rule(for key: String, isClimax: Bool) -> Rule? {
        // Storyboard beats: "<prefix>.beat-<kind>", at half the group's level (smaller than the fractures).
        if let range = key.range(of: ".beat-") {
            let prefix = String(key[..<range.lowerBound])
            guard let beat = BeatKind(rawValue: String(key[range.upperBound...])),
                  let group = storyGroup(prefix: prefix, beat: beat) else { return nil }
            // The can's hiss is a full fizz recording: further down still.
            return Rule(picks: [Pick(group: group, gain: beat == .hiss ? 0.3 : 0.5)])
        }
        switch key {
        // The press and the brand: recordings layered under the synth.
        case "press.kachunk":
            return Rule(picks: [Pick(group: "press_kachunk_latch"), Pick(group: "press_kachunk_metal", delay: 0.028)],
                        mode: .layer)
        case "press.contact": return rule("press_contact_soft", mode: .layer)
        case "press.stamp": return rule("press_stamp", mode: .layer)
        // Bubble Wrap.
        case "bubblewrap.pop": return rule("bubblewrap_pop")
        case "bubblewrap.place", "bubblewrap.contact", "bubblewrap.release", "bubblewrap.reveal", "bubblewrap.poke":
            return rule("bubblewrap_crinkle")
        // Rubber Duck.
        case "duck.honk", "duck.poke": return rule("duck_squeak")
        case "duck.failure": return rule("duck_honk", mode: .only(["bloop", "air", "wheeze"]))
        case "duck.release", "duck.reveal": return rule("duck_wheeze")
        // Jelly.
        case "jelly.failure": return rule("jelly_splat")
        case "jelly.split", "jelly.grain": return rule("jelly_squelch")
        case "jelly.place", "jelly.reveal", "jelly.release", "jelly.poke": return rule("jelly_wobble")
        // Crayon.
        // Short breaks: lifted so they stand over the bed like the others (CI: crayon 4.1 LU, egg 5.4 LU).
        case "crayon.snap": return Rule(picks: [Pick(group: "crayon_snap", gain: 1.4)])
        case "crayon.crumble", "crayon.reveal", "crayon.crush": return rule("crayon_crumb")
        case "crayon.place", "crayon.contact", "crayon.poke": return rule("crayon_tap")
        // Egg.
        case "egg.failure":
            return Rule(picks: [Pick(group: "egg_crack", gain: 1.4), Pick(group: "egg_yolk", delay: 0.05, gain: 0.8)])
        case "egg.hairline", "egg.contact", "egg.poke", "egg.grain": return rule("egg_tick")
        case "egg.crush": return rule("egg_crunch")
        case "egg.spread": return rule("egg_yolk")
        // Cake.
        case "cake.failure":
            return Rule(picks: [Pick(group: "cake_collapse"), Pick(group: "cake_squirt", delay: 0.06, gain: 0.8)])
        case "cake.icing": return rule("cake_icing")
        case "cake.reveal", "cake.grain": return rule("cake_crumb")
        // Soda can.
        case "can.buckle": return rule(isClimax ? "can_crush" : "can_buckle")
        case "can.fizz": return rule("can_open_fizz")
        case "can.grain": return rule("can_crumple")
        case "can.place", "can.contact", "can.poke": return rule("can_tink")
        // Gummy bear.
        case "gummy.failure": return rule("gummy_split")
        case "gummy.spread", "gummy.poke", "gummy.crush": return rule("gummy_squish")
        case "gummy.place", "gummy.reveal": return rule("gummy_boing")
        // Glass bottle.
        case "glass.crack": return rule("glass_crack")
        case "glass.failure":
            return Rule(picks: [Pick(group: "glass_shatter"), Pick(group: "glass_debris", delay: 0.15, gain: 0.8)])
        case "glass.crunch", "glass.crush": return rule("glass_grit")
        case "glass.grain": return rule("glass_tick")
        case "glass.place", "glass.contact": return rule("glass_contact")
        case "glass.release", "glass.reveal", "glass.poke": return rule("glass_tink")
        // The Unsquishable (steel).
        case "unsquishable.groan": return rule("steel_groan")
        case "unsquishable.failure":
            return Rule(picks: [Pick(group: "steel_crash"), Pick(group: "steel_boing", delay: 0.3, gain: 0.8)])
        case "unsquishable.place", "unsquishable.contact", "unsquishable.poke": return rule("steel_clink")
        default: return nil
        }
    }

    /// The recording for one storyboard beat of one object (nil: the quiet synth grain stays). Grains and details only.
    static func storyGroup(prefix: String, beat: BeatKind) -> String? {
        switch (prefix, beat) {
        case ("bubblewrap", .ripple): "bubblewrap_popsmall"
        case ("bubblewrap", .crease), ("bubblewrap", .settle): "bubblewrap_crinkle"
        case ("duck", .squeak), ("duck", .crease): "duck_squeak"
        case ("jelly", .wobble), ("jelly", .ooze), ("jelly", .fling), ("jelly", .bulge): "jelly_squelch"
        case ("crayon", .bend), ("crayon", .fold), ("crayon", .chip), ("crayon", .smear), ("crayon", .crease): "crayon_crumb"
        case ("egg", .crack), ("egg", .branch), ("egg", .chip), ("egg", .strain): "egg_tick"
        case ("egg", .ooze), ("egg", .fling), ("egg", .wobble): "jelly_squelch"
        case ("cake", .chip), ("cake", .crease), ("cake", .bulge), ("cake", .settle): "cake_crumb"
        case ("can", .crease), ("can", .buckle), ("can", .strain): "can_crumple"
        case ("can", .hiss): "can_open_fizz"
        case ("gummy", .strand), ("gummy", .stretch), ("gummy", .bulge): "gummy_squish"
        case ("glass", .crack), ("glass", .strain), ("glass", .chip): "glass_tick"
        case ("glass", .settle): "glass_grit"
        case ("unsquishable", .chip): "steel_clink"
        default: nil
        }
    }

    /// The recorded strain loop under load before the failure (nil: the synthesised noise bed stays).
    static func strainLoop(_ kind: ObjectKind) -> String? {
        switch kind {
        case .bubbleWrap: "bubblewrap_crinkle_loop"
        case .jelly: "jelly_squelch_loop"
        case .cakeSlice: "cake_squish_loop"
        case .sodaCan: "can_strain_loop"
        case .gummyBear: "gummy_stretch_loop"
        case .glassBottle: "glass_creak_loop"
        case .unsquishable: "steel_groan_loop"
        case .rubberDuck, .crayon, .egg: nil
        }
    }

    /// The recorded bed after the failure (the can's fizz, the duck's wheeze).
    static func crushLoop(_ kind: ObjectKind) -> String? {
        switch kind {
        case .sodaCan: "can_fizz_loop"
        case .rubberDuck: "duck_wheeze_loop"
        default: nil
        }
    }

    /// "<prefix>.<event>" and the layer of a slot id ("glass.failure.body" → ("glass.failure", "body")).
    static func key(of slot: SoundSlot) -> (key: String, layer: String)? {
        let parts = slot.id.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        return (parts[0] + "." + parts[1], parts[2])
    }

    /// Mode `.replace`: the synth layers a recording competes with.
    static func competes(_ command: SynthCommand) -> Bool {
        switch command {
        case .noise, .crunch: true
        case .tone(let spec): spec.start >= 300
        case .ring, .sample, .hush: false
        }
    }
}

/// Voices a cue with the recorded foley: one seeded pick per group (round-robin, never the same file twice in a row),
/// ± the group's pitch spread and ±2 dB, at the per-press tone. The haptics follow the chosen file's measured onsets
/// (SOUND-2 §4.1 "the sample is the score"): a shatter's vibration is its shard strikes. Built once by the CueBook and
/// handed to both controllers, so sound and touch share the pick. Pure: seeded presses (share clips) replay exactly.
enum SampleVoicing {
    static func voice(_ cue: FeedbackCue, keys explicit: [String]? = nil, style: SoundStyle, speed: Float,
                      library: SampleLibrary?, dice: FeedbackDice) -> FeedbackCue {
        guard let library, !library.groups.isEmpty else { return cue }
        var keys: [String] = explicit ?? []
        if explicit == nil {
            for layer in cue.sounds {
                if let key = SampleMap.key(of: layer.slot)?.key, !keys.contains(key) { keys.append(key) }
            }
        }
        var voiced = cue
        var hapticsReplaced = false
        for key in keys {
            guard let rule = SampleMap.rule(for: key, isClimax: cue.isClimax) else { continue }
            let replaced: [Int] = voiced.sounds.indices.filter { index in
                guard let parts = SampleMap.key(of: voiced.sounds[index].slot), parts.key == key else { return false }
                switch rule.mode {
                case .replace: return SampleMap.competes(voiced.sounds[index].command)
                case .layer: return false
                case .only(let names): return names.contains(parts.layer)
                }
            }
            let eventLayers = voiced.sounds.filter { SampleMap.key(of: $0.slot)?.key == key }
            if rule.mode != .layer && replaced.isEmpty { continue }
            let start = eventLayers.map(\.command.delay).min() ?? 0

            var layers: [SoundLayer] = []
            var notes: [HapticNote] = []
            for (index, pick) in rule.picks.enumerated() {
                guard let group = library.groups[pick.group], !group.files.isEmpty else { continue }
                if group.wet && style == .soft { continue } // Soft keeps liquid synthesised
                let file = group.files[dice.pick(group.files.count, for: SoundSlot("sample.\(group.name)"))]
                let layered: Float = rule.mode == .layer ? 0.8 : 1
                let gain = pow(10, group.gainDb / 20) * AudioMix.sampleBus * dice.level() * pick.gain * layered
                let delay = start + pick.delay
                let spec = SampleSpec(data: file.data, rate: dice.semitones(group.pitch) * dice.tone, gain: min(gain, 1),
                                      delay: delay)
                layers.append(SoundLayer(slot: SoundSlot("\(key).sample-\(group.name)"), command: .sample(spec),
                                         isWet: group.wet))
                notes += hapticNotes(file.onsets, role: index == 0 ? group.role : "tail", delay: Double(delay),
                                     speed: speed, layered: rule.mode == .layer)
            }
            guard !layers.isEmpty else { continue }
            let drop = Set(replaced)
            voiced.sounds = voiced.sounds.indices.filter { !drop.contains($0) }.map { voiced.sounds[$0] } + layers
            guard !notes.isEmpty else { continue }
            if rule.mode == .layer || hapticsReplaced {
                voiced.haptics += notes
            } else {
                // The recording's own hits replace the recipe's transients; its continuous tails and bodies stay.
                voiced.haptics = voiced.haptics.filter { $0.kind == .continuous } + notes
                hapticsReplaced = true
            }
        }
        return voiced
    }

    /// The recorded strain loop (before the failure) or crush loop (after it) for this frame, or nil to keep the
    /// synthesised noise bed. Volume follows strain and closing speed; the rate (pitch) rises a little with both.
    /// Holding still keeps the tension audible (EXPERIENCE-PLAN: the bed holds, never fades to silence).
    static func loopBed(kind: ObjectKind, progress: Float, speed: Float, holding: Bool, failed: Bool, opening: Bool,
                        closing: Bool, style: SoundStyle, library: SampleLibrary?)
        -> (data: SampleData, gain: Float, rate: Float)? {
        guard let library, !opening else { return nil }
        let name = failed ? SampleMap.crushLoop(kind) : SampleMap.strainLoop(kind)
        guard let name, let group = library.groups[name], let file = group.files.first,
              !(group.wet && style == .soft) else { return nil }
        let trim = pow(10, group.gainDb / 20) * AudioMix.loopBus
        let v = min(max(speed, 0), 1)
        let level: Float
        if failed {
            level = closing ? 0.35 + 0.65 * v : 0.25
        } else {
            let p = min(max(progress, 0), 1)
            level = pow(p, 1.3) * (holding ? 0.5 : 0.55 + 0.45 * v)
        }
        return (file.data, level * trim, 0.92 + 0.16 * v + 0.06 * min(max(progress, 0), 1))
    }

    /// SOUND-2 §4.2, per manifest class: grains one tick at their attack (with speed), details a soft kiss, bodies
    /// every hit, heroes every hit with the first forced to full, tails (debris) at 40 %.
    static func hapticNotes(_ onsets: [SampleLibrary.HapticOnset], role: String, delay: Double, speed: Float,
                            layered: Bool) -> [HapticNote] {
        guard let first = onsets.first else { return [] }
        let v = min(max(speed, 0), 1)
        let all = Array(onsets.prefix(24))
        var notes: [HapticNote]
        switch role {
        case "grain":
            notes = [HapticNote.tap(first.intensity * (0.35 + 0.65 * v), first.sharpness, at: first.time)]
        case "detail":
            notes = [HapticNote.tap(min(first.intensity * 0.6, 0.5), first.sharpness, at: first.time)]
        case "hero":
            notes = all.enumerated().map { index, onset -> HapticNote in
                HapticNote.tap(index == 0 ? 1 : onset.intensity, onset.sharpness, at: onset.time)
            }
        case "tail":
            notes = all.map { HapticNote.tap($0.intensity * 0.4, $0.sharpness, at: $0.time) }
        default: // body, and anything new
            notes = all.map { HapticNote.tap($0.intensity, $0.sharpness, at: $0.time) }
        }
        return notes.map { note in
            var shifted = note
            shifted.time += delay
            if layered && role != "detail" { shifted.intensity *= 0.7 }
            return shifted
        }
    }
}
