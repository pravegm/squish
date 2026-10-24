import SwiftUI
import UIKit

// S2 Press Room console (design/EXPERIENCE-PLAN.md decision 8, UX-AUDIT-2 §4.2): the doors are always on the console,
// on the anvil's free edge (tabletop) or under the right thumb (book), never near the crease.
//
//   [☰ Menu]  [▣ BUBBLE WRAP · POPS ⌃]  [▦ Shelf 3/10]  [⚙]
//
// Mid-press the keys stay where they are, dimmed and inert, so the console still says what's on the anvil and where
// the way out is (easing off the press brings them back).

struct PressConsole: View {
    let director: PressDirector
    let landscape: Bool
    /// Increment to make the Shelf key hop once (first discovery).
    let hop: Int
    /// Increment when a card lands in the Shelf key.
    let bump: Int
    /// Increment to make the tray chip bounce once (S6: a new object is on the anvil).
    var trayPulse = 0
    /// During a collect: only the Shelf key shows, so the card has somewhere real to land.
    var shelfOnly = false
    /// Mid-press: every key dims to 40 % and stops taking taps.
    var pressing = false
    let onMenu: () -> Void
    let onTray: () -> Void
    let onShelf: () -> Void
    let onSettings: () -> Void
    /// The Shelf key's global frame, for the collect flight.
    var onShelfFrame: (CGRect) -> Void = { _ in }
    var width: CGFloat = 360

    var body: some View {
        let spacing = Theme.s2
        Group {
            if landscape {
                VStack(spacing: Theme.s3) {
                    HStack(spacing: spacing) {
                        menuKey
                        Spacer(minLength: 0)
                        settingsKey
                    }
                    tray
                    shelf
                }
            } else {
                // Fixed slots, so nothing shifts between objects (VISUAL-REVIEW-1 #14). Narrow consoles (a 6.1" phone,
                // the Duo's book page) stack the Menu key's word under its icon instead of beside it.
                let menuWidth = labelledMenu ? ConsoleMetrics.menuWidth : ConsoleMetrics.compactMenuWidth
                let flexible = max(120, width - menuWidth - Theme.hit - spacing * 3)
                HStack(spacing: spacing) {
                    menuKey.frame(width: menuWidth)
                    tray.frame(width: flexible * 0.62)
                    shelf.frame(width: flexible * 0.38)
                    settingsKey
                }
            }
        }
        .frame(width: width)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var hidden: Bool { shelfOnly }

    /// Room for "☰ Menu" side by side (the Duo's tabletop console is 455 pt; a 6.1" phone's ~370).
    private var labelledMenu: Bool { landscape || width >= 420 }

    private var menuKey: some View {
        MenuKeycap(compact: !labelledMenu, action: onMenu)
            .opacity(hidden ? 0 : (pressing ? 0.4 : 1))
            .allowsHitTesting(!hidden && !pressing)
            .accessibilityHidden(hidden)
    }

    private var settingsKey: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(.subheadline, weight: .semibold))
        }
        .buttonStyle(KeycapStyle(kind: .console, round: true))
        .opacity(hidden ? 0 : (pressing ? 0.4 : 1))
        .allowsHitTesting(!hidden && !pressing)
        .accessibilityHidden(hidden)
        .accessibilityLabel("Settings")
        .accessibilityHint("Sound, vibration, captions and how to press.")
    }

    private var tray: some View {
        TrayChip(kind: director.currentKind, golden: director.variant.isGolden, pulse: trayPulse, action: onTray)
            .opacity(hidden ? 0 : (pressing ? 0.4 : 1))
            .allowsHitTesting(!hidden && !pressing)
            .accessibilityHidden(hidden)
    }

    private var shelf: some View {
        ShelfKey(pressedCount: director.collection.pressedKindsCount,
                 total: ObjectKind.allCases.count, hop: hop, bump: bump, onOpen: onShelf)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onShelfFrame($0) }
            .opacity(pressing ? 0.4 : 1)
            .allowsHitTesting(!pressing)
    }
}

enum ConsoleMetrics {
    /// The labelled ☰ Menu key: wide enough for the icon and the word, so nobody has to guess what it is.
    static let menuWidth: CGFloat = 96
    /// The stacked form: the icon with MENU under it.
    static let compactMenuWidth: CGFloat = 58
}

/// "☰ Menu": a dark console keycap with a yellow icon. Labelled, because the founder looked for a menu and found none.
/// `compact` stacks the word under the icon for narrow consoles.
struct MenuKeycap: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    VStack(spacing: 0) {
                        icon
                        Text("MENU")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                    }
                } else {
                    HStack(spacing: 6) {
                        icon
                        Text("Menu")
                    }
                }
            }
            // The keycap's own padding is for words; this key is narrow on purpose.
            .padding(.horizontal, -10)
        }
        .buttonStyle(KeycapStyle(kind: .console, fullWidth: true))
        .accessibilityLabel("Menu")
        .accessibilityHint("Resume, objects, shelf, how to press, settings and about.")
    }

    private var icon: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(Theme.yellow)
    }
}

/// The object tray (S2): what's on the anvil, as a picture, its name and its verb. Tap to open the Museum (S3).
struct TrayChip: View {
    let kind: ObjectKind
    var golden = false
    var pulse = 0
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounced = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s2) {
                ObjectTile(kind: kind, cornerRadius: 7, golden: golden)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    // The short name ("DUCK"), so the Duo's narrow book-page console never cuts it off.
                    ViewThatFits(in: .horizontal) {
                        Text(kind.chipName)
                        Text(kind.trayName)
                    }
                    .font(Theme.label)
                    .foregroundStyle(Theme.graphite)
                    Text(kind.verb.uppercased())
                        .font(Theme.micro)
                        .tracking(Theme.microTracking)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.leading, -10)
            .padding(.trailing, -6)
        }
        .buttonStyle(KeycapStyle(kind: .chip, fullWidth: true))
        .scaleEffect(bounced ? 1.06 : 1)
        .animation(reduceMotion ? nil : Theme.hop, value: bounced)
        .onChange(of: pulse) { _, _ in
            guard !reduceMotion else { return }
            Task { @MainActor in
                bounced = true
                try? await Task.sleep(for: .milliseconds(220))
                bounced = false
            }
        }
        .accessibilityLabel("Object: \(kind.displayName). \(kind.verb).")
        .accessibilityHint("Opens the Museum of Pressed Things, to choose what goes on the anvil.")
    }
}

/// The Shelf key on the console: dark keycap with the count, always shown ("0/10" included). Swipe up also opens the
/// Shelf. Hops once on discovery (a yellow glow under Reduce Motion), and sinks in when a collected card lands.
struct ShelfKey: View {
    let pressedCount: Int
    let total: Int
    let hop: Int
    let bump: Int
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    @State private var sunk = false
    @State private var glow = false

    var body: some View {
        Button(action: onOpen) {
            // "Shelf" and a count badge (never "0/10", which reads as a score of zero), dropping the icon, then the word,
            // when the key is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    icon
                    Text("Shelf").fixedSize()
                    count
                }
                HStack(spacing: 5) {
                    Text("Shelf").fixedSize()
                    count
                }
                HStack(spacing: 5) {
                    icon
                    count
                }
            }
            .padding(.horizontal, -10)
        }
        .buttonStyle(KeycapStyle(kind: .console, fullWidth: true))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.yellow, lineWidth: 2)
                .padding(.bottom, 4)
                .opacity(glow ? 0.8 : 0)
                .allowsHitTesting(false)
        }
        .scaleEffect(sunk ? 0.94 : 1)
        .offset(y: (lifted ? -10 : 0) + (sunk ? 3 : 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -24 { onOpen() }
            }
        )
        .onChange(of: hop) { _, _ in
            Task { @MainActor in
                if reduceMotion {
                    for _ in 0..<2 {
                        withAnimation(.easeInOut(duration: 0.5)) { glow = true }
                        try? await Task.sleep(for: .milliseconds(500))
                        withAnimation(.easeInOut(duration: 0.5)) { glow = false }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                } else {
                    withAnimation(Theme.hop) { lifted = true }
                    try? await Task.sleep(for: .milliseconds(240))
                    withAnimation(Theme.hop) { lifted = false }
                }
            }
        }
        .onChange(of: bump) { _, _ in
            Task { @MainActor in
                withAnimation(Theme.keyDown) { sunk = true }
                UIFeel.success()
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(Theme.keyUp) { sunk = false }
            }
        }
        .accessibilityLabel("Shelf")
        .accessibilityValue(pressedCount == 0 ? "Empty so far" : "\(pressedCount) of \(total) objects pressed")
        .accessibilityHint("Opens your collection: objects, squished specimens and achievements.")
    }

    private var icon: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
    }

    /// A small yellow badge with how many objects are on the shelf; hidden while it's empty.
    @ViewBuilder
    private var count: some View {
        if pressedCount > 0 {
            Text("\(pressedCount)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.graphite)
                .contentTransition(.numericText())
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Theme.yellow))
                .fixedSize()
                .animation(Theme.pop(reduceMotion), value: pressedCount)
        }
    }
}

/// "NEXT UNLOCK · SODA CAN · press 3 different things · 1/3", a small graphite plate just above the console, so the
/// press room always says what playing gets you next. Nothing when everything is open.
struct NextUnlockLine: View {
    let collection: CollectionStore

    var body: some View {
        if let next = collection.nextUnlock {
            let name = next.kind.isSecret ? "???" : next.kind.displayName.uppercased()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.yellow)
                // The longest form that fits: the full line, then without the label, then name and count only.
                ViewThatFits(in: .horizontal) {
                    unlockText("NEXT UNLOCK · \(name) · \(next.progress.line.uppercased())")
                    unlockText("NEXT: \(name) · \(next.progress.line.uppercased())")
                    unlockText("NEXT: \(name) · \(min(next.progress.done, next.progress.total))/\(next.progress.total)")
                }
                ProgressPips(fraction: next.progress.fraction)
                    .frame(width: 34, height: 4)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.graphite.opacity(0.88)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next unlock: \(next.kind.isSecret ? "a secret object" : next.kind.displayName). \(next.progress.task.capitalizedFirstLetter), \(min(next.progress.done, next.progress.total)) of \(next.progress.total).")
        }
    }
}

extension NextUnlockLine {
    fileprivate func unlockText(_ text: String) -> some View {
        Text(text.gluingDotSeparators)
            .font(Theme.micro)
            .tracking(Theme.microTracking * 0.5)
            .foregroundStyle(Theme.paper.opacity(0.92))
            .lineLimit(1)
            .fixedSize()
    }
}

/// A 4 pt progress bar in yellow on a dark track.
struct ProgressPips: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.yellow)
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

extension ObjectKind {
    /// The tray chip's short name for narrow consoles (the Duo's book page): "DUCK", never "RUBBER…".
    var trayName: String {
        switch self {
        case .bubbleWrap: "BUBBLES"
        case .rubberDuck: "DUCK"
        case .jelly: "JELLY"
        case .crayon: "CRAYONS"
        case .egg: "EGG"
        case .cakeSlice: "CAKE"
        case .sodaCan: "SODA CAN"
        case .gummyBear: "GUMMY"
        case .glassBottle: "BOTTLE"
        case .unsquishable: "STEEL BALL"
        }
    }
}

extension String {
    /// "press 3 different things" → "Press 3 different things".
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
