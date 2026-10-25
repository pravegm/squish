import SwiftUI

// S1 Welcome & Fold Lesson and the first-five-presses coach (UX-AUDIT-2 §4.2, EXPERIENCE-2 §D2, EXPERIENCE-PLAN
// decision 2). First run only, under 10 s, replayable from the Menu: a live pose card whose hinge glyph mirrors the real
// angle, a sound-check line, then a practice Bubble Wrap press with "Close it slowly" and a first-pop celebration.
// The angles come from the engine's PressConfig (contact ~106°, the first pop just after), never hard-coded here.

/// The press-room lesson's memory: whether the first run has been taught, and the replay switch.
enum LessonMemory {
    static let doneKey = "squish.lesson.done"

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }
}

/// Where the hinge is, in the lesson's terms.
enum LessonPose: Equatable {
    /// Below the arming angle: stand it up and open it wide first.
    case tooClosed
    /// Wide open and ready: close it slowly.
    case ready
    /// Lying flat: lift the top half.
    case flat
    /// No hinge (or Press without folding): drag down.
    case touch

    static func of(angle: Double, config: PressConfig, hinge: Bool) -> LessonPose {
        guard hinge else { return .touch }
        if angle >= 172 { return .flat }
        if angle < config.armAngleMin { return .tooClosed }
        return .ready
    }
}

/// The live pose card (S1 beat 1 and 2). It reads the engine itself, so only this card redraws at the hinge's rate.
struct FoldLessonCard: View {
    let engine: PressEngine
    let hinge: Bool
    let book: Bool
    let soundLine: String
    var onHelp: (() -> Void)?

    var body: some View {
        let config = engine.config
        let pose = LessonPose.of(angle: engine.angle, config: config, hinge: hinge)
        let contact = FoldCurve.contactAngle(start: config.armAngleMax, config: config)
        let firstFracture = ObjectKind.bubbleWrap.profile.fractures.first ?? 0.03
        let firstPop = FoldCurve.angle(forCompression: firstFracture, start: config.armAngleMax, config: config)
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Text("HOW TO PRESS")
                    .accessibilityHidden(true)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                if let onHelp {
                    Button(action: onHelp) {
                        Text("MORE HELP")
                            .font(Theme.micro)
                            .tracking(Theme.microTracking)
                            .foregroundStyle(Theme.graphite)
                            .padding(.horizontal, Theme.s2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More help")
                    .accessibilityHint("Shows how to press in tabletop, book and drag modes.")
                }
            }
            VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(alignment: .center, spacing: Theme.s4) {
                Group {
                    if pose == .touch {
                        DragGlyph()
                    } else {
                        HingeGlyph(angle: engine.angle, ready: pose == .ready,
                                   readyFrom: config.armAngleMin, contact: contact, firstPop: firstPop)
                    }
                }
                .frame(width: 112, height: 88)
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text(Self.title(pose, book: book))
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.detail(pose, book: book).keepingLastWordsTogether)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(Theme.fade, value: pose)
            }
            Rectangle().fill(Theme.paperEdge).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.graphite)
                Text(soundLine.keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text((hinge ? "It's all on-screen. Never close your phone on real things."
                        : "It's all on-screen. Never squish real things.").keepingLastWordsTogether)
                .font(Theme.micro)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            // The card's words as one element; MORE HELP stays its own 44 pt button beside it (`.contain`).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("How to press. \(Self.title(pose, book: book)) \(Self.detail(pose, book: book)) \(soundLine)")
            .accessibilitySortPriority(1)
        }
        .padding(Theme.s4)
        .background { PaperBackground().clipShape(shape).elevation(.e3) }
        .topHighlight(cornerRadius: Theme.cardRadius)
        .overlay(alignment: .topLeading) {
            Capsule().fill(Theme.yellow).frame(width: 36, height: 4).offset(x: Theme.s4, y: -2)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }

    static func title(_ pose: LessonPose, book: Bool) -> String {
        switch pose {
        case .tooClosed: book ? "Hold it like a book. Open it wide." : "Stand it up like a tiny laptop."
        case .flat: book ? "Fold it a little, like a book." : "Lift the top half a little."
        case .ready: "Now close it slowly."
        case .touch: "Drag down on the press, slowly."
        }
    }

    static func detail(_ pose: LessonPose, book: Bool = false) -> String {
        switch pose {
        case .tooClosed: "Open it wide first. The press starts as you close it."
        case .flat: book ? "Either page can be the lid. The press starts as it folds." : "Like a laptop. The top half is the press."
        case .ready: "The bubble wrap starts popping just after the halves meet it."
        case .touch: "The slower you go, the better it sounds."
        }
    }
}

/// A side view of the phone mirroring the real hinge (S1): the base on a table line, the lid at the live angle, a
/// green band where the press is ready, and two small marks where the squish starts and the first pop lands.
struct HingeGlyph: View {
    let angle: Double
    var ready = false
    /// The band from here to flat (180°) is "ready".
    var readyFrom: Double = 130
    /// Where the lid meets the object.
    var contact: Double?
    /// Where the first bubble pops.
    var firstPop: Double?
    /// Dark backgrounds (the cover display).
    var onDark = false

    var body: some View {
        Canvas { context, size in
            let length = min(size.width * 0.42, size.height * 0.95)
            let pivot = CGPoint(x: size.width * 0.5, y: size.height * 0.86)
            func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                // Measured from the base (pointing right) toward the lid, counter-clockwise: 180° = flat open.
                return CGPoint(x: pivot.x + CGFloat(cos(a)) * radius, y: pivot.y - CGFloat(sin(a)) * radius)
            }
            let ink = onDark ? Theme.paper : Theme.graphite
            // The ready band: an arc from `readyFrom` to 180°.
            var band = Path()
            band.move(to: point(readyFrom, length * 0.98))
            for degrees in stride(from: readyFrom, through: 180, by: 2) {
                band.addLine(to: point(degrees, length * 0.98))
            }
            band.addLine(to: point(180, length * 0.98))
            context.stroke(band, with: .color(Theme.lampGreen.opacity(ready ? 0.9 : 0.45)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))
            // Contact and first-pop marks on the arc.
            for (mark, tint) in [(contact, Theme.yellow), (firstPop, Theme.stamp)] {
                guard let mark else { continue }
                var tick = Path()
                tick.move(to: point(mark, length * 0.86))
                tick.addLine(to: point(mark, length * 1.1))
                context.stroke(tick, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            // The table.
            var table = Path()
            table.move(to: CGPoint(x: size.width * 0.04, y: pivot.y + 5))
            table.addLine(to: CGPoint(x: size.width * 0.96, y: pivot.y + 5))
            context.stroke(table, with: .color(ink.opacity(0.25)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // The base (anvil half) and the object on it.
            var base = Path()
            base.move(to: pivot)
            base.addLine(to: point(0, length))
            context.stroke(base, with: .color(ink), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            let blob = CGRect(x: pivot.x + length * 0.42, y: pivot.y - 11, width: length * 0.3, height: 8)
            context.fill(Path(roundedRect: blob, cornerRadius: 4), with: .color(Theme.tint(for: .bubbleWrap)))
            // The lid (platen half), at the live angle.
            var lid = Path()
            lid.move(to: pivot)
            lid.addLine(to: point(min(max(angle, 0), 180), length))
            context.stroke(lid, with: .color(ready ? Theme.yellow : ink.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - 5, y: pivot.y - 5, width: 10, height: 10)),
                         with: .color(Theme.steel))
        }
        .accessibilityHidden(true)
    }
}

/// The drag press's glyph: a finger arrow sliding down a phone outline (Reduce Motion: still).
struct DragGlyph: View {
    var onDark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.5 : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8)
            let ink = onDark ? Theme.paper : Theme.graphite
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ink, lineWidth: 3)
                    .frame(width: 46, height: 80)
                Image(systemName: "hand.point.down.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.yellow)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
                    .offset(y: -22 + CGFloat(t) * 40)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Coaching (the first 5 presses)

/// One line for whatever the press is doing (EXPERIENCE-PLAN decision 2: coaching for the first 5 presses). Pure.
struct CoachLine: Equatable {
    var title: String
    var detail: String
    var symbol: String
    /// The first pop of the first press: the lesson's celebration.
    var celebrate = false

    static let presses = 5

    /// How long the hand must rest past the break before "Shut it all the way" (EXPERIENCE-REVIEW-1 #6).
    static let stallAfterBreak: Double = 1.5

    /// Coaching never talks over the press (EXPERIENCE-REVIEW-1 #6): it speaks before contact, then stays silent from
    /// contact through the tell, the break and its settle, and speaks again only once the user has stalled after the
    /// break, or at the seal.
    /// - `pressIndex`: completed presses before this one (0 = the lesson's practice press, which also gets
    ///   "Close it slowly"; presses 2–5 only react: EASY… on a fast approach, EASED OFF on a reopen under load).
    /// - `broken`: the object has given (its failure, or every fracture for things that never fail).
    /// - `stalledAfterBreak`: broken, and the hand has rested at least `stallAfterBreak` seconds since.
    static func line(phase: PressPhase, compression: Double, depth: Double, contactDepth: Double, broken: Bool,
                     stalledAfterBreak: Bool, closingSpeed: Double, slamSpeed: Double, touch: Bool,
                     pressIndex: Int) -> CoachLine? {
        guard pressIndex < presses else { return nil }
        switch phase {
        case .sealed:
            return CoachLine(title: "KA-CHUNK!", detail: touch ? "Let go to see what's left." : "Now open it to see what's left.",
                             symbol: "seal.fill")
        case .revealing, .idle:
            return nil
        case .armed, .pressing:
            break
        }
        guard depth > 0.01 else { return nil }
        let touching = compression > 0 || depth >= contactDepth
        if !touching {
            if closingSpeed > slamSpeed * 0.6 {
                return CoachLine(title: "EASY…", detail: "Slower is better. Much better.", symbol: "tortoise.fill")
            }
            guard pressIndex == 0 else { return nil }
            return CoachLine(title: "CLOSE IT SLOWLY", detail: touch ? "Keep dragging down… slowly." : "Keep closing… slowly.",
                             symbol: "tortoise.fill")
        }
        if broken {
            guard stalledAfterBreak else { return nil }
            return CoachLine(title: "ALL THE WAY", detail: touch ? "Drag right to the bottom to seal it." : "Shut it all the way to seal it.",
                             symbol: "arrow.down.to.line")
        }
        // Loaded and not broken: the press moment. Only a reopen is worth a word.
        if closingSpeed < -25 {
            return CoachLine(title: "EASED OFF", detail: touch ? "Drag again to keep going." : "Close again to keep going.",
                             symbol: "pause.fill")
        }
        return nil
    }
}

/// The coach line in the toast slot, with a little burst for the first pop (Reduce Motion: no burst).
struct CoachLineView: View {
    let line: CoachLine
    var compact = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ToastView(title: line.title, detail: line.detail, glyph: .symbol(line.symbol),
                  accent: line.celebrate ? Theme.stamp : Theme.yellow, compact: compact)
            .overlay(alignment: .leading) {
                if line.celebrate && !reduceMotion {
                    ZStack {
                        ForEach(0..<8, id: \.self) { index in
                            Sparkle()
                                .fill(index % 2 == 0 ? Theme.yellow : Theme.stamp)
                                .frame(width: 10, height: 10)
                                .offset(x: burst ? 34 : 6)
                                .rotationEffect(.degrees(Double(index) * 45))
                                .opacity(burst ? 0 : 1)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .offset(x: Theme.s2 + 4 + 12)
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.7)) { burst = true }
                    }
                }
            }
            .scaleEffect(line.celebrate && !reduceMotion ? (burst ? 1 : 1.08) : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: burst)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(line.title.capitalized). \(line.detail)")
    }
}
