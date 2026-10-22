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

    @Test func signatureCaptions() {
        #expect(Captions.failure(.glassBottle) == "SMASH!")
        #expect(Captions.failure(.sodaCan) == "FSSSHT!")
        #expect(Captions.failure(.unsquishable) == "CLANG… CRACK?!")
        #expect(Captions.fracture(.bubbleWrap, index: 0) == "POP!")
        #expect(Captions.fracture(.rubberDuck, index: 0) == "HONK!")
    }
}
