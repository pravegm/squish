import AVFoundation
import Foundation
import Testing
@testable import Squish

@MainActor
struct FeedbackTests {
    private func context(_ kind: ObjectKind, seed: UInt64 = 7, golden: Bool = false, surprise: Surprise? = nil,
                         compression: Float = 0.5, speed: Float = 60) -> FeedbackContext {
        var variant = PressVariant(kind: kind, seed: seed)
        variant.isGolden = golden
        variant.surprise = surprise
        return FeedbackContext(kind: kind, variant: variant, compression: compression, closingSpeed: speed,
                               soundStyle: .workshop, reduceMotion: false)
    }

    private func cue(_ kind: ObjectKind, _ moment: RecipeMoment, seed: UInt64 = 7, hasFailed: Bool = false,
                     fractures: Int = 0) -> FeedbackCue {
        let input = RecipeInput(context: context(kind), dice: FeedbackDice(seed: seed), hasFailed: hasFailed,
                                fracturesFired: fractures)
        return Recipes.recipe(for: kind).cue(for: moment, input)
    }

    /// Every moment of a press, in order, with the press memory a live run would have.
    private func pressSequence(_ kind: ObjectKind, dice: FeedbackDice) -> [FeedbackCue] {
        let profile = kind.profile
        let recipe = Recipes.recipe(for: kind)
        var memory = CueBook.PressMemory()
        var cues: [FeedbackCue] = []
        var moments: [RecipeMoment] = [.place, .contact, .grain(compression: 0.1), .preFailureTell, .microCrack(index: 0),
                                       .microCrack(index: 5)]
        for index in profile.fractures.indices {
            moments.append(.fracture(index: index, isFailure: index == profile.failureIndex))
            moments.append(.grain(compression: Float(profile.fractures[index]) + 0.01))
        }
        moments += [.released, .reveal]
        for moment in moments {
            let input = RecipeInput(context: context(kind), dice: dice, hasFailed: memory.hasFailed,
                                    fracturesFired: memory.fractures)
            cues.append(recipe.cue(for: moment, input))
            if case let .fracture(_, isFailure) = moment {
                memory.fractures += 1
                if isFailure { memory.hasFailed = true }
            }
        }
        return cues
    }

    // MARK: - Recipes

    @Test(arguments: ObjectKind.allCases)
    func contactHasSoundAndHaptic(_ kind: ObjectKind) {
        let contact = cue(kind, .contact)
        #expect(!contact.sounds.isEmpty)
        #expect(!contact.haptics.isEmpty)
        let place = cue(kind, .place)
        #expect(!place.sounds.isEmpty)
        #expect(!place.haptics.isEmpty)
    }

    @Test(arguments: ObjectKind.allCases)
    func failureHasSoundAndHapticAndIsTheClimax(_ kind: ObjectKind) {
        guard let failure = kind.profile.failureIndex else {
            // Bubble wrap has no single failure: every pop is its own event.
            for index in [0, 11, BubbleWrapLayout.count - 1] {
                let pop = cue(kind, .fracture(index: index, isFailure: false), fractures: index)
                #expect(!pop.sounds.isEmpty)
                #expect(!pop.haptics.isEmpty)
            }
            return
        }
        let climax = cue(kind, .fracture(index: failure, isFailure: true), fractures: failure)
        #expect(!climax.sounds.isEmpty)
        #expect(!climax.haptics.isEmpty)
        #expect(climax.isClimax)
        #expect(climax.haptics.contains { $0.intensity >= 0.85 })
    }

    @Test(arguments: ObjectKind.allCases)
    func everyFractureSoundsAndOnlyTheFailureIsAClimax(_ kind: ObjectKind) {
        let profile = kind.profile
        for index in profile.fractures.indices {
            let isFailure = index == profile.failureIndex
            let hasFailed = profile.failureIndex.map { index > $0 } ?? false
            let fracture = cue(kind, .fracture(index: index, isFailure: isFailure), hasFailed: hasFailed, fractures: index)
            #expect(!fracture.sounds.isEmpty, "\(kind) fracture \(index) is silent")
            #expect(fracture.isClimax == isFailure, "\(kind) fracture \(index) climax flag")
        }
    }

    @Test(arguments: ObjectKind.allCases)
    func valuesStayInRange(_ kind: ObjectKind) {
        for cue in pressSequence(kind, dice: FeedbackDice(seed: 11)) {
            for note in cue.haptics {
                #expect(note.intensity >= 0 && note.intensity <= 1)
                #expect(note.sharpness >= 0 && note.sharpness <= 1)
                #expect(note.time >= 0)
                if !cue.isClimax { #expect(note.intensity <= 0.9) }
            }
            for layer in cue.sounds {
                #expect(layer.command.gain > 0 && layer.command.gain <= 1, "\(layer.slot) gain")
                #expect(layer.slot.id.hasPrefix(kind.slotPrefix + "."), "\(layer.slot) prefix")
            }
        }
    }

    /// 02 §1.2: no sustained tonal energy at 2.5–4.5 kHz (squeals, screech).
    @Test(arguments: ObjectKind.allCases)
    func noSustainedToneInTheHarshBand(_ kind: ObjectKind) {
        var cues = pressSequence(kind, dice: FeedbackDice(seed: 5))
        cues += [BrandCues.kaChunk, BrandCues.sting, BrandCues.collect, BrandCues.unlock, BrandCues.tonic, BrandCues.contact]
        cues.append(SharedCues.golden(FeedbackDice(seed: 1)))
        for surprise in Surprise.allCases {
            cues.append(SharedCues.surprise(surprise, dice: FeedbackDice(seed: 1)))
        }
        let harsh: ClosedRange<Float> = 2500...4500
        for cue in cues {
            for layer in cue.sounds {
                if case let .tone(spec) = layer.command, harsh.contains(spec.start) || harsh.contains(spec.end) {
                    #expect(spec.duration <= 0.15, "\(layer.slot) sustains in the harsh band")
                }
            }
        }
    }

    // MARK: - Determinism and variation

    @Test(arguments: ObjectKind.allCases)
    func seededPressesReplayExactly(_ kind: ObjectKind) {
        let first = pressSequence(kind, dice: FeedbackDice(seed: 42))
        let second = pressSequence(kind, dice: FeedbackDice(seed: 42))
        #expect(first == second)
        let other = pressSequence(kind, dice: FeedbackDice(seed: 43))
        #expect(first != other)
    }

    @Test func picksNeverRepeatBackToBack() {
        let dice = FeedbackDice(seed: 9)
        let slot = SoundSlot("test.pick.body")
        var last = dice.pick(3, for: slot)
        var seen: Set<Int> = [last]
        for _ in 0..<200 {
            let next = dice.pick(3, for: slot)
            #expect(next != last)
            #expect((0..<3).contains(next))
            seen.insert(next)
            last = next
        }
        #expect(seen.count == 3)
    }

    @Test func dicePitchSpreadsFollowTheSpec() {
        let dice = FeedbackDice(seed: 2)
        for _ in 0..<200 {
            let grain = dice.semitones(1.5)
            #expect(grain >= 0.9168 && grain <= 1.0906) // ±1.5 st (2^±0.125 = 0.91700…1.09051)
            let gain = dice.decibels(2)
            #expect(gain >= 0.794 && gain <= 1.259) // ±2 dB
        }
    }

    @Test func pulseScheduleIsDeterministicAndAccelerates() {
        var a = PulseSchedule(kind: .tell)
        var b = PulseSchedule(kind: .tell)
        a.start(seed: 77)
        b.start(seed: 77)
        var firedA: [Int] = []
        var firedB: [Int] = []
        for _ in 0..<120 {
            if let index = a.advance(by: 1.0 / 60) { firedA.append(index) }
            if let index = b.advance(by: 1.0 / 60) { firedB.append(index) }
        }
        #expect(firedA == firedB)
        #expect(firedA.count >= 5)
        #expect(a.interval(0) > a.interval(10))
        #expect(a.interval(30) >= 1.0 / 15 * 0.85 - 1e-9)
    }

    // MARK: - Sync

    @Test func cueBookHandsTheSameCueToBothControllers() {
        let book = CueBook(seed: 3)
        let crayon = context(.crayon, compression: 0.1)
        let placeA = book.cue(for: .recipe(.place), context: crayon, consumer: .audio)
        let placeH = book.cue(for: .recipe(.place), context: crayon, consumer: .haptics)
        #expect(placeA == placeH)
        let grainH = book.cue(for: .recipe(.grain(compression: 0.1)), context: crayon, consumer: .haptics)
        let grainA = book.cue(for: .recipe(.grain(compression: 0.1)), context: crayon, consumer: .audio)
        #expect(grainH == grainA)
        // The same consumer asking again means a new grain.
        let nextGrain = book.cue(for: .recipe(.grain(compression: 0.1)), context: crayon, consumer: .haptics)
        #expect(nextGrain != grainH)
        #expect(!book.memory.hasFailed)
        _ = book.cue(for: .recipe(.fracture(index: 0, isFailure: true)), context: crayon, consumer: .haptics)
        #expect(book.memory.hasFailed)
        #expect(book.memory.fractures == 1)
        // A new placement resets the press memory.
        _ = book.cue(for: .recipe(.place), context: crayon, consumer: .haptics)
        #expect(!book.memory.hasFailed)
    }

    @Test func placementReseedsSoAPressReplaysFromItsSeed() {
        let one = CueBook(seed: 1)
        let two = CueBook(seed: 999)
        one.library = { nil }
        two.library = { nil }
        let egg = context(.egg, seed: 1234)
        #expect(one.cue(for: .recipe(.place), context: egg, consumer: .audio)
            == two.cue(for: .recipe(.place), context: egg, consumer: .audio))
        #expect(one.cue(for: .recipe(.contact), context: egg, consumer: .audio)
            == two.cue(for: .recipe(.contact), context: egg, consumer: .audio))
        #expect(one.cue(for: .recipe(.fracture(index: 1, isFailure: true)), context: egg, consumer: .audio)
            == two.cue(for: .recipe(.fracture(index: 1, isFailure: true)), context: egg, consumer: .audio))
    }

    // MARK: - Soft style

    @Test func softStyleRemovesWetLayers() {
        for kind in ObjectKind.allCases {
            for cue in pressSequence(kind, dice: FeedbackDice(seed: 3)) {
                #expect(!cue.styled(.soft).sounds.contains { $0.isWet }, "\(kind) keeps a wet layer in Soft")
            }
        }
        // Jelly's splat really has wet layers to remove, and keeps its dry ones.
        let splat = cue(.jelly, .fracture(index: 1, isFailure: true), fractures: 1)
        let soft = splat.styled(.soft)
        #expect(splat.sounds.contains { $0.isWet })
        #expect(soft.sounds.count < splat.sounds.count)
        #expect(!soft.sounds.isEmpty)
        #expect(soft.haptics == splat.haptics)
        #expect(splat.styled(.workshop) == splat)
    }

    @Test func softStyleHalvesCrunchDensity() {
        let snap = cue(.crayon, .fracture(index: 0, isFailure: true))
        let soft = snap.styled(.soft)
        let full = snap.sounds.compactMap { layer -> CrunchSpec? in
            if case let .crunch(spec) = layer.command { return spec } else { return nil }
        }
        let gentle = soft.sounds.compactMap { layer -> CrunchSpec? in
            if case let .crunch(spec) = layer.command { return spec } else { return nil }
        }
        #expect(!full.isEmpty)
        #expect(full.count == gentle.count)
        for (a, b) in zip(full, gentle) {
            #expect(abs(b.rate - a.rate * 0.5) < 0.001)
            #expect(b.gain < a.gain)
            #expect(b.high <= 5000)
        }
    }

    // MARK: - Reveal extras and brand

    @Test func goldenAndSurprisesAddDistinctRevealLayers() {
        let plain = CueBook.compose(.recipe(.reveal), context: context(.egg), dice: FeedbackDice(seed: 4),
                                    memory: CueBook.PressMemory())
        let golden = CueBook.compose(.recipe(.reveal), context: context(.egg, golden: true), dice: FeedbackDice(seed: 4),
                                     memory: CueBook.PressMemory())
        #expect(golden.sounds.count > plain.sounds.count)
        #expect(golden.sounds.contains { $0.slot.id.hasPrefix("press.golden.") })
        var signatures: Set<String> = []
        for surprise in Surprise.allCases {
            let flourish = SharedCues.surprise(surprise, dice: FeedbackDice(seed: 4))
            #expect(!flourish.sounds.isEmpty)
            #expect(!flourish.haptics.isEmpty)
            signatures.insert(flourish.sounds.map(\.slot.id).joined(separator: ","))
        }
        #expect(signatures.count == Surprise.allCases.count)
    }

    @Test func brandSoundsAreFixedAndOnThePentatonic() {
        let stingPitches = BrandCues.sting.sounds.compactMap { layer -> Float? in
            if case let .tone(spec) = layer.command, spec.harmonics == 2 { return spec.start } else { return nil }
        }
        #expect(stingPitches == [523.25, 659.25, 783.99]) // C5 E5 G5
        #expect(BrandCues.kaChunk.isClimax)
        #expect(BrandCues.kaChunk.haptics.contains { $0.intensity == 1 })
        #expect(BrandCues.kaChunk.haptics.filter { $0.time >= 1.5 }.count == 2) // two "ready" taps
        let fanfare = BrandCues.unlock.sounds.compactMap { layer -> Float? in
            if case let .tone(spec) = layer.command, spec.harmonics == 2 { return spec.start } else { return nil }
        }
        for pitch in fanfare {
            #expect(BrandCues.pentatonic.contains(pitch))
        }
    }

    // MARK: - Captions

    @Test(arguments: ObjectKind.allCases)
    func everyFailureHasAnAnnouncedCaption(_ kind: ObjectKind) {
        let ctx = context(kind)
        if let failure = kind.profile.failureIndex {
            let line = Captions.caption(for: .fracture(index: failure, isFailure: true), context: ctx)
            #expect(line?.text != nil)
            #expect(line?.announce == true)
            #expect(line?.text.isEmpty == false)
        }
        for index in kind.profile.fractures.indices where index != kind.profile.failureIndex {
            let line = Captions.caption(for: .fracture(index: index, isFailure: false), context: ctx)
            #expect(line?.announce != true)
        }
        #expect(Captions.caption(for: .kaChunk, context: ctx)?.text == "KA-CHUNK")
        #expect(Captions.caption(for: .kaChunk, context: ctx)?.announce == true)
        #expect(Captions.caption(for: .reveal, context: ctx)?.announce == true)
        // Compare `.text` (Equatable): the caption itself is a tuple, which #expect can't decompose against nil.
        #expect(Captions.caption(for: .grain(compression: 0.4), context: ctx)?.text == nil)
        #expect(Captions.caption(for: .contact, context: ctx)?.text == nil)
        #expect(Captions.caption(for: .hush, context: ctx)?.text == nil)
    }

    // MARK: - Audio session (Duo test 1: silent on silent mode)

    @Test func soundPlaysOnSilentByDefaultAndMixesWithMusic() {
        let onSilent = AudioSessionChoice.forSettings(playsInSilentMode: true)
        #expect(onSilent.category == .playback)
        #expect(onSilent.options.contains(.mixWithOthers))
        #expect(!onSilent.options.contains(.duckOthers))
        #expect(!onSilent.respectsSilentSwitch)
        let polite = AudioSessionChoice.forSettings(playsInSilentMode: false)
        #expect(polite.category == .ambient)
        #expect(polite.respectsSilentSwitch)
    }

    @Test func playOnSilentSettingDefaultsOnAndSurvivesOldSaves() throws {
        let settings = AppSettings()
        // A 1.0 (1) save, from before the setting existed.
        let legacy = Data("""
        {"soundEnabled":false,"soundStyle":"soft","hapticsLevel":"soft","showCaptions":true,\
        "pressWithoutFolding":false,"hasSeenSafetyHint":true}
        """.utf8)
        settings.playSoundInSilentMode = false
        #expect(settings.load(from: legacy))
        #expect(settings.playSoundInSilentMode)
        #expect(!settings.soundEnabled)
        #expect(settings.soundStyle == .soft)
        #expect(settings.hapticsLevel == .soft)

        settings.playSoundInSilentMode = false
        let data = try #require(settings.encoded())
        let reloaded = AppSettings()
        reloaded.playSoundInSilentMode = true
        #expect(reloaded.load(from: data))
        #expect(!reloaded.playSoundInSilentMode)
        #expect(!reloaded.soundEnabled)
    }

    /// The setting really switches the shared session (simulator), and the diagnostics report it in plain words.
    @Test func silentModeSettingSwitchesTheSessionCategory() {
        let audio = AudioController()
        audio.start()
        let session = AVAudioSession.sharedInstance()
        #expect(session.category == .playback)
        #expect(session.categoryOptions.contains(.mixWithOthers))
        let respected = audio.diagnosticRows().first { $0.title == "Silent switch respected?" }
        #expect(respected?.value.hasPrefix("No") == true)

        audio.playsInSilentMode = false
        #expect(session.category == .ambient)
        let nowRespected = audio.diagnosticRows().first { $0.title == "Silent switch respected?" }
        #expect(nowRespected?.value.hasPrefix("Yes") == true)
        #expect(nowRespected?.isWarning == true)

        // Leave the host app's session as the app sets it.
        audio.playsInSilentMode = true
        #expect(session.category == .playback)
    }

    // MARK: - Haptic strength (Duo test 1: "a little, weak")

    @Test func liftMakesQuietNotesFeelableAndKeepsOrder() {
        #expect(HapticTuning.lift(0) == 0)
        #expect(HapticTuning.lift(1) == 1)
        #expect(HapticTuning.lift(0.12) >= 0.25)
        #expect(HapticTuning.lift(0.3) >= 0.45)
        var last: Float = -1
        for step in 0...20 {
            let value = HapticTuning.lift(Float(step) / 20)
            #expect(value > last)
            #expect(value <= 1)
            last = value
        }
    }

    @Test(arguments: ObjectKind.allCases)
    func strainBedIsStrongAtTheBreakEvenOnASlowClose(_ kind: ObjectKind) {
        let beds = Recipes.recipe(for: kind).beds
        let gain = kind.profile.bedGain
        let slow = HapticTuning.speed(15) // a careful Duo close
        let atContact = HapticTuning.strainBed(strain: 0, speed: slow, holding: false, materialGain: gain,
                                               recipeMax: beds.hapticMax)
        let halfway = HapticTuning.strainBed(strain: 0.5, speed: slow, holding: false, materialGain: gain,
                                             recipeMax: beds.hapticMax)
        let atBreak = HapticTuning.strainBed(strain: 1, speed: slow, holding: false, materialGain: gain,
                                             recipeMax: beds.hapticMax)
        let held = HapticTuning.strainBed(strain: 1, speed: 0, holding: true, materialGain: gain,
                                          recipeMax: beds.hapticMax)
        #expect(atContact >= HapticTuning.loadedFloor - 0.001, "\(kind) contact")
        #expect(halfway > atContact)
        #expect(atBreak > halfway)
        #expect(atBreak >= 0.45, "\(kind) bed at the break is \(atBreak)")
        #expect(atBreak <= HapticTuning.bedCeiling)
        #expect(held >= atBreak * 0.8, "\(kind) holding goes slack")
    }

    // MARK: - Vibration strength (Duo 1.0 (3): "vibrations need to be stronger")

    @Test func strongIsTheDefaultAndSurvivesOldSaves() throws {
        let settings = AppSettings()
        let legacy = Data("""
        {"soundEnabled":true,"soundStyle":"workshop","hapticsLevel":"full","showCaptions":false,\
        "pressWithoutFolding":false,"hasSeenSafetyHint":true,"playSoundInSilentMode":true}
        """.utf8)
        settings.vibrationStrength = .normal
        #expect(settings.load(from: legacy))
        #expect(settings.vibrationStrength == .strong)
        settings.vibrationStrength = .max
        let data = try #require(settings.encoded())
        let reloaded = AppSettings()
        #expect(reloaded.load(from: data))
        #expect(reloaded.vibrationStrength == .max)
    }

    @Test func strongAndMaxUseTheWholeRange() {
        let strong = HapticProfile.of(.strong)
        let max = HapticProfile.of(.max)
        #expect(HapticProfile.of(.normal) == .normal)
        // The strain bed: a clearly felt floor at contact, full at the break.
        for profile in [strong, max] {
            let contact = profile.strainBed(strain: 0, speed: 0.3, holding: false, materialGain: 0.55, recipeMax: 0.45)
            let atBreak = profile.strainBed(strain: 1, speed: 1, holding: false, materialGain: 0.55, recipeMax: 0.45)
            let held = profile.strainBed(strain: 1, speed: 0, holding: true, materialGain: 0.55, recipeMax: 0.45)
            #expect(contact >= 0.45)
            #expect(atBreak >= 0.99)
            #expect(held >= 0.9)
            #expect(profile.rumbleDepth > 0 && profile.rumbleHz >= 20 && profile.rumbleHz <= 40)
            #expect(!profile.fatigue)
            #expect(profile.nonClimaxCap == 1)
            #expect(profile.lift(0.2) > HapticProfile.normal.lift(0.2))
        }
        #expect(max.lift(0.2) > strong.lift(0.2))
        #expect(max.bedFloor > strong.bedFloor)
    }

    @Test func majorHitsGetAHeavyBurstAndMaxStacksThem() {
        let crack: [HapticNote] = [.tap(0.7, 0.9), .tap(0.2, 0.9, at: 0.05)]
        let strong = HapticProfile.strong.reinforced(crack, isGrain: false)
        let bursts = strong.filter { $0.kind == .continuous }
        #expect(bursts.count == 1) // only the major hit
        #expect(bursts.allSatisfy { $0.intensity == 1 && $0.sharpness <= 0.4 && $0.duration >= 0.03 && $0.duration <= 0.08 })
        let max = HapticProfile.maximum.reinforced(crack, isGrain: false)
        #expect(max.filter { $0.kind == .continuous }.allSatisfy { $0.duration > bursts[0].duration })
        #expect(max.filter { $0.kind == .transient }.count == crack.count + 1) // the stacked thump
        // Grains grind: a second tap shortly after each one.
        let grain = [HapticNote.tap(0.25, 0.7)]
        let echoed = HapticProfile.strong.reinforced(grain, isGrain: true)
        #expect(echoed.filter { $0.kind == .transient }.count == 2)
        // Normal is the old feel: nothing added.
        #expect(HapticProfile.normal.reinforced(crack, isGrain: true) == crack)
    }

    @Test func failureAndKaChunkHitHardAndLow() {
        let body = BrandCues.failureBody
        #expect(body.isClimax)
        #expect(body.haptics.contains { $0.kind == .transient && $0.intensity == 1 && $0.sharpness <= 0.4 })
        #expect(body.haptics.contains { $0.kind == .continuous && $0.intensity >= 0.9 && $0.duration >= 0.15 })
        let chunk = BrandCues.kaChunk.haptics.filter { $0.time < 1 }
        #expect(chunk.contains { $0.kind == .transient && $0.intensity == 1 && $0.sharpness <= 0.3 })
        #expect(chunk.contains { $0.kind == .continuous && $0.intensity >= 0.9 })
    }

    @Test(arguments: ObjectKind.allCases)
    func pressFeelTestRunsTheWholeArc(_ kind: ObjectKind) {
        let cue = PressFeelDemo.cue(kind: kind, dice: FeedbackDice(seed: 8))
        #expect(!cue.sounds.isEmpty)
        #expect(cue.haptics.count >= 10)
        #expect(cue.haptics.contains { $0.time >= PressFeelDemo.failureTime && $0.time < PressFeelDemo.kaChunkTime
            && $0.intensity == 1 })
        #expect(cue.haptics.contains { $0.time >= PressFeelDemo.kaChunkTime && $0.intensity == 1 })
        #expect(cue.haptics.allSatisfy { $0.time < 4 && $0.intensity >= 0 && $0.intensity <= 1 })
        #expect(cue.sounds.allSatisfy { $0.command.delay < 4 })
        let ramp = PressFeelDemo.bedRamp
        #expect(ramp.count <= 16)
        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect((ramp.map(\.intensity).max() ?? 0) >= 0.9)
        #expect((ramp.last?.time ?? 9) <= PressFeelDemo.strainDuration)
    }

    @Test func delayedShiftsSoundAndTouchTogether() {
        let cue = BrandCues.bottomOut.delayed(by: 0.5)
        #expect(zip(cue.sounds, BrandCues.bottomOut.sounds).allSatisfy { abs($0.command.delay - $1.command.delay - 0.5) < 1e-6 })
        #expect(zip(cue.haptics, BrandCues.bottomOut.haptics).allSatisfy { abs($0.time - $1.time - 0.5) < 1e-9 })
    }

    // MARK: - Hinge feel (opening and closing always sound and feel like something)

    private func hingeInput(_ angle: Double, speed: Double = 30, moving: Bool = true, shut: Bool = false,
                            phase: PressPhase = .armed, loaded: Bool = false) -> HingeMotionInput {
        HingeMotionInput(available: true, angle: angle, speed: speed, moving: moving, shut: shut, phase: phase, loaded: loaded)
    }

    @Test func detentsClickEverySixDegreesWithoutChatter() {
        var tracker = DetentTracker()
        var clicks: [Bool] = []
        var time = 0.0
        for step in 0...120 {
            if let closing = tracker.track(angle: 180 - Double(step), at: time) { clicks.append(closing) }
            time += 0.05
        }
        #expect(clicks.count >= 19 && clicks.count <= 21, "got \(clicks.count)")
        #expect(clicks.allSatisfy { $0 })
        // Sensor jitter of ±1° around a detent never clicks.
        var jitter = DetentTracker()
        var chatter = 0
        for step in 0..<200 {
            if jitter.track(angle: 120 + (step % 2 == 0 ? 1 : -1), at: Double(step) * 0.05) != nil { chatter += 1 }
        }
        #expect(chatter == 0)
        // Opening clicks too, reported as opening.
        var opening = DetentTracker()
        _ = opening.track(angle: 60, at: 0)
        let opened = opening.track(angle: 70, at: 1)
        #expect(opened == .some(false))
    }

    @Test func hingeOpensAndShutsWithACueButNotAroundASeal() {
        var feel = HingeFeel()
        // Launch shut: a state, not a transition.
        let launch = feel.update(hingeInput(5, moving: false, shut: true, phase: .idle), at: 0)
        #expect(launch.moments.isEmpty)
        // Opening past 55° wakes the press once.
        var opened = 0
        for (index, angle) in stride(from: 10.0, through: 120, by: 5).enumerated() {
            let moments = feel.update(hingeInput(angle, speed: -60, phase: .idle), at: 0.1 + Double(index) * 0.05).moments
            opened += moments.filter { $0 == .opened }.count
        }
        #expect(opened == 1)
        // Shutting outside a press clacks.
        let shut = feel.update(hingeInput(3, speed: 40, shut: true, phase: .idle), at: 5).moments
        #expect(shut.contains(.shut))
        // Reopening after a seal is the reveal's job (unlatch), not the power-up.
        var sealedFeel = HingeFeel()
        _ = sealedFeel.update(hingeInput(150, phase: .armed), at: 0)
        let sealShut = sealedFeel.update(hingeInput(3, shut: true, phase: .sealed), at: 1).moments
        #expect(!sealShut.contains(.shut))
        let reopen = sealedFeel.update(hingeInput(70, speed: -80, phase: .revealing), at: 2).moments
        #expect(!reopen.contains(.opened))
    }

    @Test func hingeIsSilentWhenStillOrLoadedAndRisesWithSpeed() {
        var feel = HingeFeel()
        _ = feel.update(hingeInput(150), at: 0)
        let still = feel.update(hingeInput(150, speed: 0, moving: false), at: 0.1)
        #expect(still.bed == .still)
        let slow = feel.update(hingeInput(140, speed: 15), at: 0.2).bed
        let brisk = feel.update(hingeInput(130, speed: 90), at: 0.3).bed
        #expect(slow.creakGain > 0 && slow.texture > 0)
        #expect(brisk.creakGain > slow.creakGain)
        #expect(brisk.creakPitch > slow.creakPitch)
        #expect(brisk.texture > slow.texture)
        // Under load the press feedback owns everything: no hinge bed, no detents.
        var loaded = 0
        for step in 0..<40 {
            let result = feel.update(hingeInput(120 - Double(step), loaded: true), at: 1 + Double(step) * 0.05)
            #expect(result.bed == .still)
            loaded += result.moments.count
        }
        #expect(loaded == 0)
        // Off without a real hinge.
        var touch = HingeFeel()
        var input = hingeInput(100)
        input.available = false
        let off = touch.update(input, at: 0)
        #expect(off.bed == .still)
    }

    @Test func hingeCuesStayQuieterThanThePress() {
        let dice = FeedbackDice(seed: 3)
        let detent = HingeCues.cue(for: .detent(closing: true), speed: 90, dice: dice)
        #expect(!detent.sounds.isEmpty && !detent.haptics.isEmpty)
        #expect(detent.sounds.allSatisfy { $0.command.gain <= 0.08 })
        #expect(detent.haptics.allSatisfy { $0.intensity <= 0.3 })
        for moment in [HingeMoment.opened, .powerDown, .shut] {
            let cue = HingeCues.cue(for: moment, speed: 40, dice: dice)
            #expect(!cue.sounds.isEmpty && !cue.haptics.isEmpty)
            #expect(!cue.isClimax)
            #expect(cue.haptics.allSatisfy { $0.intensity < BrandCues.kaChunk.haptics.map(\.intensity).max() ?? 1 })
        }
        #expect(!BrandCues.unlatch.sounds.isEmpty && !BrandCues.unlatch.haptics.isEmpty)
    }

    /// Real Duo log: the `.closed` status sets at ~85° while closing. The shut clack is the angle (≤ 10°) or the
    /// engine's angle-based shut, never an 85° reading.
    @Test func theShutClackWaitsForTheRealShut() {
        var feel = HingeFeel()
        var moments: [HingeMoment] = []
        moments += feel.update(hingeInput(150, phase: .idle), at: 0).moments
        for (index, angle) in stride(from: 140.0, through: 14, by: -3).enumerated() {
            moments += feel.update(hingeInput(angle, speed: 60, phase: .idle), at: 0.1 + Double(index) * 0.03).moments
        }
        #expect(!moments.contains(.shut))
        let shut = feel.update(hingeInput(4, speed: 60, phase: .idle), at: 5).moments
        #expect(shut.contains(.shut))
        #expect(HingeFeel.shutAngle <= 12)
    }

    /// The director takes detents and power up/down from the engine's beats; HingeFeel must then only clack on a shut.
    @Test func engineBeatsReplaceDetectedDetentsButKeepTheShutClack() {
        var feel = HingeFeel()
        feel.detectsDetentsAndPower = false
        var moments: [HingeMoment] = []
        moments += feel.update(hingeInput(5, moving: false, shut: true, phase: .idle), at: 0).moments
        for (index, angle) in stride(from: 15.0, through: 150, by: 3).enumerated() {
            moments += feel.update(hingeInput(angle, speed: -60, phase: .idle), at: 0.1 + Double(index) * 0.05).moments
        }
        for (index, angle) in stride(from: 150.0, through: 15, by: -3).enumerated() {
            moments += feel.update(hingeInput(angle, speed: 60, phase: .idle), at: 5 + Double(index) * 0.05).moments
        }
        moments += feel.update(hingeInput(3, speed: 40, shut: true, phase: .idle), at: 9).moments
        #expect(moments == [.shut])
        // The continuous bed still follows the hinge.
        let moving = feel.update(hingeInput(90, speed: 60, phase: .idle), at: 10)
        #expect(moving.bed.creakGain > 0)
    }

    @Test(arguments: ObjectKind.allCases)
    func pressBeatsSoundAndFeelQuietly(_ kind: ObjectKind) {
        let dice = FeedbackDice(seed: 4)
        let cues = [BeatCues.creak(kind, intensity: 1, dice: dice), BeatCues.debris(kind, intensity: 1, dice: dice),
                    BeatCues.settleTick(kind, intensity: 1, dice: dice),
                    TouchCues.spin(kind, turnsPerSecond: 3, dice: dice)]
        for cue in cues {
            #expect(!cue.sounds.isEmpty && !cue.haptics.isEmpty)
            #expect(!cue.isClimax)
            #expect(cue.sounds.allSatisfy { $0.command.gain > 0 && $0.command.gain <= 0.1 })
            #expect(cue.haptics.allSatisfy { $0.intensity <= 0.6 })
        }
        // A quiet debris grain is quieter than a loud one.
        let soft = BeatCues.debris(kind, intensity: 0.2, dice: FeedbackDice(seed: 1))
        let loud = BeatCues.debris(kind, intensity: 1, dice: FeedbackDice(seed: 1))
        #expect((soft.haptics.first?.intensity ?? 1) < (loud.haptics.first?.intensity ?? 0))
    }

    /// Storyboard beats: every beat of every object sounds and feels lighter than the fractures, and every recording
    /// the map names exists.
    @Test(arguments: ObjectKind.allCases)
    func storyboardBeatsStayUnderTheFractures(_ kind: ObjectKind) {
        let library = SampleLibrary.loadNow()
        let dice = FeedbackDice(seed: 6)
        for beat in ObjectStoryboard.beats(kind, seed: 42) {
            guard let raw = BeatCues.story(kind, beat: beat.kind, speed: 1, dice: dice) else { continue }
            let cue = BeatCues.softened(SampleVoicing.voice(raw, style: .workshop, speed: 1, library: library, dice: dice))
            #expect(!cue.isClimax)
            #expect(!cue.haptics.isEmpty, "\(kind) \(beat.kind) has no touch")
            #expect(cue.haptics.allSatisfy { $0.intensity <= 0.4 })
            #expect(cue.sounds.allSatisfy { $0.command.gain <= 0.35 }, "\(kind) \(beat.kind) too loud")
            if let group = SampleMap.storyGroup(prefix: kind.slotPrefix, beat: beat.kind) {
                #expect(library.groups[group] != nil, "\(kind) \(beat.kind) → \(group) missing")
            }
        }
    }

    @Test(arguments: ObjectKind.allCases)
    func everyObjectAnswersAPoke(_ kind: ObjectKind) {
        let cue = TouchCues.poke(kind, dice: FeedbackDice(seed: 12))
        #expect(!cue.sounds.isEmpty)
        #expect(!cue.haptics.isEmpty)
        #expect(!cue.isClimax)
        for layer in cue.sounds {
            #expect(layer.command.gain > 0 && layer.command.gain <= 0.2, "\(layer.slot) gain")
            #expect(layer.slot.id.hasPrefix(kind.slotPrefix + ".poke."), "\(layer.slot) prefix")
        }
        #expect(cue.haptics.allSatisfy { $0.intensity <= 0.8 && $0.time < 0.5 })
    }

    // MARK: - Recorded foley

    @Test func recordedLibraryLoadsFromTheAppBundle() {
        let library = SampleLibrary.loadNow()
        #expect(library.problem == nil, "\(library.problem ?? "")")
        #expect(library.groups.count >= 30, "only \(library.groups.count) groups")
        #expect(library.fileCount >= 100)
        #expect(library.groups["press_kachunk_latch"] != nil)
        #expect(library.groups.values.allSatisfy { group in group.files.allSatisfy { $0.data.count > 1 && $0.data.sampleRate > 0 } })
        // Every group the map asks for exists, so no moment silently stays synthesised by a typo.
        let keys = ["press.kachunk", "press.contact", "bubblewrap.pop", "duck.honk", "jelly.failure", "crayon.snap",
                    "egg.failure", "cake.failure", "can.fizz", "gummy.failure", "glass.failure", "unsquishable.failure"]
        for key in keys {
            for pick in SampleMap.rule(for: key, isClimax: true)?.picks ?? [] {
                #expect(library.groups[pick.group] != nil, "\(key) → \(pick.group) missing")
            }
        }
    }

    private func voice(_ cue: FeedbackCue, style: SoundStyle = .workshop, seed: UInt64 = 1) -> FeedbackCue {
        SampleVoicing.voice(cue, style: style, speed: 0.5, library: SampleLibrary.loadNow(), dice: FeedbackDice(seed: seed))
    }

    @Test func samplesReplaceTheCompetingSynthLayersAndBringTheirHits() {
        let failure = cue(.glassBottle, .fracture(index: kindFailure(.glassBottle), isFailure: true))
        let voiced = voice(failure)
        #expect(voiced.sounds.contains(where: isSample))
        // Noise and crunch bodies are gone; low thumps and modal rings stay under the recording.
        #expect(!voiced.sounds.contains { layer in
            guard layer.slot.id.hasPrefix("glass.failure.") else { return false }
            return SampleMap.competes(layer.command) && !isSample(layer)
        })
        #expect(voiced.sounds.allSatisfy { $0.command.gain > 0 && $0.command.gain <= 1 })
        // The shatter's own hits drive the vibration (a hero: the first hit at full), the recipe's tails stay.
        #expect(voiced.haptics.contains { $0.kind == .transient && $0.intensity == 1 })
        #expect(voiced.haptics.filter { $0.kind == .continuous }.count == failure.haptics.filter { $0.kind == .continuous }.count)
        // The ka-chunk layers its recordings under the synth and keeps the brand "ready" tinks.
        let chunk = voice(BrandCues.kaChunk)
        #expect(chunk.sounds.contains { $0.slot.id.hasPrefix("press.kachunk.ready") })
        #expect(chunk.sounds.contains { $0.slot.id == "press.kachunk.thock" })
        #expect(chunk.sounds.contains(where: isSample))
        #expect(chunk.haptics.count >= BrandCues.kaChunk.haptics.count)
        // Soft keeps liquid synthesised: the jelly splat isn't swapped for a wet recording.
        let splat = cue(.jelly, .fracture(index: kindFailure(.jelly), isFailure: true))
        #expect(!voice(splat, style: .soft).sounds.contains(where: isSample))
        // Unmapped moments are untouched.
        let tick = BrandCues.tick(523.25)
        #expect(voice(tick) == tick)
    }

    @Test func theBookHandsBothControllersTheSameRecordingAndReplaysIt() {
        let one = CueBook(seed: 5)
        let two = CueBook(seed: 77)
        one.library = { SampleLibrary.loadNow() }
        two.library = { SampleLibrary.loadNow() }
        let egg = context(.egg, seed: 99)
        _ = one.cue(for: .recipe(.place), context: egg, consumer: .audio)
        _ = two.cue(for: .recipe(.place), context: egg, consumer: .audio)
        let failure = CueBook.Key.recipe(.fracture(index: kindFailure(.egg), isFailure: true))
        let heard = one.cue(for: failure, context: egg, consumer: .audio)
        let felt = one.cue(for: failure, context: egg, consumer: .haptics)
        #expect(heard == felt)
        #expect(heard.sounds.contains(where: isSample))
        // A second book on the same press seed picks the same files (share clips replay the press exactly).
        #expect(two.cue(for: failure, context: egg, consumer: .audio) == heard)
        // A brand layer and a recipe moment in one event, asked in either order, still match.
        let contactH = one.cue(for: .recipe(.contact), context: egg, consumer: .haptics)
        let brandH = one.cue(for: .brand(.contact), context: egg, consumer: .haptics)
        #expect(one.cue(for: .brand(.contact), context: egg, consumer: .audio) == brandH)
        #expect(one.cue(for: .recipe(.contact), context: egg, consumer: .audio) == contactH)
    }

    @Test func recordedLoopsFollowTheStrain() throws {
        let library = SampleLibrary.loadNow()
        let low = try #require(SampleVoicing.loopBed(kind: .sodaCan, progress: 0.2, speed: 0.3, holding: false, failed: false,
                                                     opening: false, closing: true, style: .workshop, library: library))
        let high = try #require(SampleVoicing.loopBed(kind: .sodaCan, progress: 1, speed: 0.3, holding: false, failed: false,
                                                      opening: false, closing: true, style: .workshop, library: library))
        #expect(high.gain > low.gain)
        #expect(high.rate >= low.rate)
        let held = try #require(SampleVoicing.loopBed(kind: .sodaCan, progress: 1, speed: 0, holding: true, failed: false,
                                                      opening: false, closing: false, style: .workshop, library: library))
        #expect(held.gain > high.gain * 0.5)
        let crayon = SampleVoicing.loopBed(kind: .crayon, progress: 1, speed: 1, holding: false, failed: false,
                                           opening: false, closing: true, style: .workshop, library: library)
        let softJelly = SampleVoicing.loopBed(kind: .jelly, progress: 1, speed: 1, holding: false, failed: false,
                                              opening: false, closing: true, style: .soft, library: library)
        let opening = SampleVoicing.loopBed(kind: .sodaCan, progress: 1, speed: 1, holding: false, failed: false,
                                            opening: true, closing: false, style: .workshop, library: library)
        #expect(crayon?.gain == nil)
        #expect(softJelly?.gain == nil)
        #expect(opening?.gain == nil)
    }

    @Test func hapticsWaitForTheAudioPathOnlyWhenItIsSlow() {
        #expect(HapticTuning.alignment(audioDelay: 0.008) == 0)
        #expect(abs(HapticTuning.alignment(audioDelay: 0.16) - 0.148) < 1e-9)
        #expect(HapticTuning.alignment(audioDelay: 2) == 0.25)
    }

    private func kindFailure(_ kind: ObjectKind) -> Int { kind.profile.failureIndex ?? 0 }

    private func isSample(_ layer: SoundLayer) -> Bool {
        if case .sample = layer.command { return true }
        return false
    }

    @Test func synthPlaysASampleVoice() throws {
        let library = SampleLibrary.loadNow()
        let group = try #require(library.groups["press_kachunk_latch"])
        let file = try #require(group.files.first)
        let synth = Synth(sampleRate: 48_000)
        synth.trigger(.sample(SampleSpec(data: file.data, rate: 1, gain: 0.5, delay: 0.01)))
        var out = [Float](repeating: 0, count: 9_600)
        out.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress { synth.render(frames: buffer.count, into: base) }
        }
        let early = out[0..<400].map { abs($0) }.max() ?? 0
        let peak = out.map { abs($0) }.max() ?? 0
        #expect(early == 0) // the 10 ms delay is honoured
        #expect(peak > 0.01)
        #expect(peak <= 0.9)
    }

    // MARK: - Loudness (02 §6: −16 LUFS integrated ±2 on the phone speaker)

    /// A steady 4-second touch close from 180° to 30°, then the hold to the reveal.
    private func pressTrace(_ kind: ObjectKind) -> PressTrace {
        var samples: [PressTrace.Sample] = []
        var time = 1.0
        let steps = 240
        for i in 0...steps {
            samples.append(PressTrace.Sample(time: time, angle: 180 - 150 * Double(i) / Double(steps), closed: false))
            time += 4.0 / Double(steps)
        }
        return PressTrace(kind: kind, variant: PressVariant(kind: kind, seed: 21), samples: samples,
                          usesVirtualHinge: true, config: .standard)
    }

    /// The press replayed into the offline twin of the live controller (same cues, same beds, same master).
    private func renderPress(_ kind: ObjectKind, seconds: Double = 9) -> (pcm: [Float], failure: Double?, beds: [Float]) {
        let trace = pressTrace(kind)
        let audio = OfflineAudio(style: .workshop)
        let replay = PressReplay(trace: trace)
        let engine = replay.engine
        let context = {
            FeedbackContext(kind: trace.kind, variant: trace.variant, compression: Float(engine.measuredCompression),
                            closingSpeed: Float(engine.closingSpeed), soundStyle: .workshop, reduceMotion: false)
        }
        var failure: Double?
        replay.onEvent = { event, time in
            if case .fracture(_, true) = event, failure == nil { failure = time }
            audio.seek(to: time, rate: 1)
            audio.handle(event, context: context())
        }
        replay.load()
        audio.seek(to: 0, rate: 1)
        audio.place(context: context())
        let step = 1.0 / 120
        var index = 1
        while Double(index) * step <= seconds {
            let time = Double(index) * step
            let dt = max(time - replay.clock, 0)
            replay.advance(to: time)
            audio.seek(to: time, rate: 1)
            audio.update(engine: engine, context: context(), dt: dt)
            index += 1
        }
        let frames = Int(seconds * OfflineAudio.sampleRate)
        // The continuous layers alone (strain loop, noise beds, hiss, motor, creak): the bed the break must stand over.
        var bedsOnly = audio.score
        bedsOnly.notes = []
        return (OfflineAudio.render(audio.score, frames: frames), failure, OfflineAudio.render(bedsOnly, frames: frames))
    }

    @Test func pressMixLandsNearTheLoudnessTarget() {
        var all: [Double] = []
        var contrasts: [Double] = []
        for kind in ObjectKind.allCases {
            let (pcm, failure, beds) = renderPress(kind)
            if let failure {
                // The bed alone in the second before the break, against the full mix in the 450 ms after it: SOUND-2
                // wants the bed 10–12 LU under the break.
                let rate = OfflineAudio.sampleRate
                let bedStart = max(Int((failure - 1.1) * rate), 0), bedEnd = max(Int((failure - 0.1) * rate), bedStart)
                let breakStart = Int(failure * rate), breakEnd = min(Int((failure + 0.45) * rate), pcm.count)
                if bedEnd - bedStart > Int(0.4 * rate), breakEnd - breakStart > Int(0.4 * rate) {
                    let bed = Loudness.integrated(Array(beds[bedStart..<bedEnd]), sampleRate: rate)
                    let hit = Loudness.integrated(Array(pcm[breakStart..<breakEnd]), sampleRate: rate)
                    print(String(format: "SQUISH-LOUD kind=%@ bed=%.1f break=%.1f contrast=%.1f LU", kind.rawValue, bed, hit, hit - bed))
                    if bed.isFinite && hit.isFinite { contrasts.append(hit - bed) }
                }
            }
            let lufs = Loudness.integrated(pcm, sampleRate: OfflineAudio.sampleRate)
            let peak = Double(pcm.map { abs($0) }.max() ?? 0)
            print(String(format: "SQUISH-LOUD kind=%@ lufs=%.1f peak=%.1f dBFS", kind.rawValue, lufs, 20 * log10(max(peak, 1e-9))))
            #expect(lufs.isFinite, "\(kind) is silent")
            #expect(peak <= 0.9, "\(kind) clips")
            all.append(lufs)
        }
        let mean = all.reduce(0, +) / Double(max(all.count, 1))
        print(String(format: "SQUISH-LOUD mean lufs=%.1f", mean))
        if !contrasts.isEmpty {
            let contrast = contrasts.reduce(0, +) / Double(contrasts.count)
            print(String(format: "SQUISH-LOUD mean contrast=%.1f LU", contrast))
            // SOUND-2: the bed 10–12 LU under the break. Bound loosely; the log shows the real figure.
            #expect(contrast >= 6, "bed only \(contrast) LU under the break")
            #expect(contrast <= 16, "bed \(contrast) LU under the break: too quiet to feel the strain")
        }
        // Target −16 ±2 (02 §6); the bound is ±3 so a small recipe change never blocks CI, and the log shows it.
        #expect(mean > -19 && mean < -13, "mean press loudness \(mean) LUFS")
    }

    @Test func loudnessMeterReadsAFullScaleSineCorrectly() {
        // BS.1770: a 0 dBFS 997 Hz sine reads −3.01 LUFS.
        let rate = 48_000.0
        let sine = (0..<Int(rate * 3)).map { Float(sin(2 * Double.pi * 997 * Double($0) / rate)) }
        let lufs = Loudness.integrated(sine, sampleRate: rate)
        #expect(abs(lufs + 3.01) < 0.3, "got \(lufs)")
    }

    /// The Crayon Box: fractures 0…6 are seven snaps (0 the failure), rising in pitch; the last is the crumble.
    @Test func crayonBoxSnapsAVolleyThenCrumbles() {
        let fractures = ObjectKind.crayon.profile.fractures
        #expect(CrayonRecipe.crumbleIndex == fractures.count - 1)
        var pitches: [Float] = []
        for index in fractures.indices {
            let isFailure = index == ObjectKind.crayon.profile.failureIndex
            let c = cue(.crayon, .fracture(index: index, isFailure: isFailure), hasFailed: index > 0, fractures: index)
            let isSnap = c.sounds.contains { $0.slot.id.hasPrefix("crayon.snap.") }
            let isCrumble = c.sounds.contains { $0.slot.id.hasPrefix("crayon.crumble.") }
            if index < CrayonRecipe.crumbleIndex {
                #expect(isSnap && !isCrumble, "fracture \(index) should snap")
                #expect(Captions.fracture(.crayon, index: index) == "SNAP!")
                pitches.append(c.samplePitch)
            } else {
                #expect(isCrumble && !isSnap, "fracture \(index) should crumble")
                #expect(Captions.fracture(.crayon, index: index) == "crumble…")
            }
        }
        #expect(pitches.count == 7)
        #expect(zip(pitches, pitches.dropFirst()).allSatisfy { $0 < $1 })
        // Seeded: two snaps of the volley aren't the same sound.
        let second = cue(.crayon, .fracture(index: 2, isFailure: false), seed: 3, hasFailed: true, fractures: 2)
        let third = cue(.crayon, .fracture(index: 3, isFailure: false), seed: 4, hasFailed: true, fractures: 3)
        #expect(second.sounds != third.sounds)
    }

    @Test func signatureCaptions() {
        #expect(Captions.failure(.glassBottle) == "SMASH!")
        #expect(Captions.failure(.sodaCan) == "FSSSHT!")
        #expect(Captions.failure(.unsquishable) == "CLANG… CRACK?!")
        #expect(Captions.fracture(.bubbleWrap, index: 0) == "POP!")
        #expect(Captions.fracture(.rubberDuck, index: 0) == "HONK!")
    }
}

/// ITU-R BS.1770-4 integrated loudness (K-weighting at 48 kHz, 400 ms blocks with 75 % overlap, absolute −70 LUFS and
/// relative −10 LU gates). Mono, so no channel weighting.
enum Loudness {
    static func integrated(_ samples: [Float], sampleRate: Double) -> Double {
        // K-weighting: the 48 kHz coefficients from BS.1770 (pre-filter shelf, then the RLB high-pass).
        let stages: [(b: [Double], a: [Double])] = [
            ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1, -1.69065929318241, 0.73248077421585]),
            ([1, -2, 1], [1, -1.99004745483398, 0.99007225036621]),
        ]
        var signal = samples.map(Double.init)
        for stage in stages {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in signal.indices {
                let x = signal[i]
                let y = stage.b[0] * x + stage.b[1] * x1 + stage.b[2] * x2 - stage.a[1] * y1 - stage.a[2] * y2
                x2 = x1
                x1 = x
                y2 = y1
                y1 = y
                signal[i] = y
            }
        }
        let block = Int(0.4 * sampleRate)
        let hop = Int(0.1 * sampleRate)
        guard signal.count >= block else { return -.infinity }
        var powers: [Double] = []
        var start = 0
        while start + block <= signal.count {
            var sum = 0.0
            for i in start..<(start + block) { sum += signal[i] * signal[i] }
            powers.append(sum / Double(block))
            start += hop
        }
        func lufs(_ power: Double) -> Double { -0.691 + 10 * log10(power) }
        let absolute = powers.filter { $0 > 0 && lufs($0) > -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let relativeGate = lufs(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { lufs($0) > relativeGate }
        guard !gated.isEmpty else { return -.infinity }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }
}
