import Foundation

/// What the reveal's slow-mo break replay tells Feedback (`PressScene.onReplay`): when it starts, and each recorded
/// mark (contact, tell, hush, every fracture) as the replay reaches it.
enum ReplayCue {
    case started(duration: Double, speed: Double)
    case mark(PressEvent)
}

/// The reveal replay in sound and touch (EXPERIENCE-REVIEW-1 #3: "the reveal's slow-mo should be the best sound of the
/// press, not silence"). Each mark re-fires that moment of the press from a book reseeded with the press's own seed,
/// so it is the same material answer, played like slowed tape: ~8 semitones down at 0.35×, envelopes stretched to
/// match, −6 dB; a low whoosh swells under the whole replay; the break gets a softened haptic echo.
@MainActor
final class ReplayFeel {
    private var book = CueBook()
    private(set) var speed = 0.35
    private var kind = ObjectKind.bubbleWrap
    private var variant = PressVariant(kind: .bubbleWrap, seed: 1)
    private var style = SoundStyle.workshop
    private var active = false

    /// Slowed-tape pitch for a replay at `speed`: 0.35× → 0.62 (−8.2 st). Real tape would be −18 st: too far for a
    /// phone speaker, so it is eased (`speed^0.45`), never below an octave down.
    nonisolated static func pitch(for speed: Double) -> Float {
        Float(min(max(pow(min(max(speed, 0.05), 1), 0.45), 0.5), 1))
    }

    /// The replay began: reseed for this press, and return the whoosh that swells under it.
    func start(kind: ObjectKind, variant: PressVariant, style: SoundStyle, speed: Double, duration: Double) -> FeedbackCue {
        self.kind = kind
        self.variant = variant
        self.style = style
        self.speed = speed
        active = true
        book = CueBook()
        book.library = { SampleLibrary.loaded }
        _ = book.cue(for: .recipe(.place), context: context(), consumer: .audio)
        return Self.whoosh(duration: duration)
    }

    func stop() {
        active = false
    }

    /// One mark of the replay: its sound (slowed) and, for fractures, a softened touch.
    func cues(for event: PressEvent) -> (sound: FeedbackCue, touch: FeedbackCue?)? {
        guard active, let moment = RecipeMoment(event) else { return nil }
        var cue = book.cue(for: .recipe(moment), context: context(), consumer: .audio)
        var touch: FeedbackCue?
        switch event {
        case .fracture(_, true):
            cue.add(BrandCues.tonic)
            touch = Self.echo(cue.adding(BrandCues.failureBody), speed: speed, strength: 0.45)
        case .fracture:
            touch = Self.echo(cue, speed: speed, strength: 0.25)
        default:
            break
        }
        return (Self.slowed(cue, speed: speed), touch)
    }

    private func context() -> FeedbackContext {
        FeedbackContext(kind: kind, variant: variant, compression: 0.9, closingSpeed: 40, soundStyle: style,
                        reduceMotion: false)
    }

    /// The cue as slowed tape: lower, longer, −6 dB; no haptics (the echo is separate).
    nonisolated static func slowed(_ cue: FeedbackCue, speed: Double) -> FeedbackCue {
        let p = pitch(for: speed)
        var slow = cue
        slow.haptics = []
        slow.isClimax = false
        slow.sounds = cue.sounds.map { layer in
            var lower = layer
            lower.command = OfflineAudio.retimed(layer.command, pitch: p).scaled(0.5)
            return lower
        }
        return slow
    }

    /// A softened, stretched haptic memory of the moment, capped at `strength` (never a second climax).
    nonisolated static func echo(_ cue: FeedbackCue, speed: Double, strength: Float) -> FeedbackCue {
        let stretch = 1 / Double(pitch(for: speed))
        var echo = FeedbackCue()
        echo.haptics = cue.haptics.prefix(24).map { note in
            var soft = note
            soft.intensity = min(note.intensity * strength, strength)
            soft.time = note.time * stretch
            soft.duration = note.duration * stretch
            return soft
        }
        return echo
    }

    /// A low swell under the whole replay: the room holding its breath, then letting go.
    nonisolated static func whoosh(duration: Double) -> FeedbackCue {
        let d = Float(max(duration, 0.5))
        let slot = { (layer: String) in SoundSlot.press("replay", layer) }
        return FeedbackCue(sounds: [
            .noise(slot("air"), .bandPass, 900, q: 0.8, attack: d * 0.4, decay: d * 0.12, gain: 0.05, sweepTo: 260,
                   sweepTime: d),
            .tone(slot("sub"), 140, to: 96, glide: d, duration: d, attack: d * 0.35, decay: 0.4, gain: 0.05, harmonics: 4),
        ])
    }
}
