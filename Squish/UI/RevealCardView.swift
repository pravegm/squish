import SwiftUI
import UIKit

/// The reveal (VISUAL-TARGET §6.8, bible §3.1 beats 11–12). Portrait: the 3:4 specimen card drops into the
/// 6–44% band (over the lifted ram, so the flattened object stays visible on the anvil), one toast at a time
/// in 80–86%, and Again / Share / Next keycaps on the console (86–95%). Landscape: card in the left 30% column,
/// console in the right 22% column. On collect, the card shrinks into the Shelf key.
struct RevealCardView: View {
    let outcome: RecordOutcome
    let collection: CollectionStore
    /// Hinge trace for the share clip, when one is stored for this specimen.
    let trace: PressTrace?
    /// Set by RootView when Next/Again was tapped: the card flies into the Shelf key.
    let collecting: Bool
    let onNext: () -> Void
    let onAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var share = SpecimenShareModel()
    @State private var cardIn = false
    @State private var toastIndex = -1
    @State private var actionsIn = false
    @State private var choosingShare = false

    /// The live record (it gains its thumbnail ~1 s after the reveal).
    private var specimen: SpecimenRecord { collection.specimen(withID: outcome.specimen.id) ?? outcome.specimen }

    private struct Toast: Identifiable {
        let id: String
        let title: String
        let detail: String
        let glyph: ToastView.Glyph
        let accent: Color
    }

    private var toasts: [Toast] {
        var list = outcome.newlyUnlocked.map { kind in
            Toast(id: "unlock-\(kind.rawValue)", title: "NEW OBJECT UNLOCKED",
                  detail: "\(kind.displayName) · up next", glyph: .object(kind), accent: Theme.tint(for: kind))
        }
        list += outcome.newAchievements.map { achievement in
            Toast(id: "ach-\(achievement.rawValue)", title: "ACHIEVEMENT · \(achievement.title.uppercased())",
                  detail: achievement.detail, glyph: .symbol(achievement.symbolName), accent: Theme.yellow)
        }
        return list
    }

    var body: some View {
        GeometryReader { proxy in
            let bands = ScreenBands(proxy)
            if bands.isLandscape {
                landscape(bands)
            } else {
                portrait(bands)
            }
        }
        .modifier(SpecimenSharingChrome(model: share))
        .confirmationDialog("Share this specimen", isPresented: $choosingShare, titleVisibility: .hidden) {
            if let trace {
                Button("Share Clip") { share.shareClip(trace: trace, specimen: specimen) }
            }
            Button("Share Image") { share.shareImage(specimen: specimen, thumbnail: collection.thumbnail(for: specimen)) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: choreograph)
    }

    // MARK: Layouts

    private func portrait(_ bands: ScreenBands) -> some View {
        let bandHeight = bands.height(0.06, 0.44)
        let width = min(bands.fullWidth * 0.84, 340, bandHeight * 0.75)
        let cardHeight = width / 0.75
        let cardCenterY = bands.y(0.06) + bandHeight / 2
        let shelfAnchor = UnitPoint(x: 0.5 + 70 / width, y: (bands.y(0.905) - (cardCenterY - cardHeight / 2)) / cardHeight)
        return ZStack {
            card(width: width, collectAnchor: shelfAnchor)
                .position(x: bands.size.width / 2, y: cardCenterY)
            toastSlot
                .frame(maxWidth: 420)
                .padding(.horizontal, bands.margin)
                .position(x: bands.size.width / 2, y: bands.y(0.83))
            actions(landscape: false)
                .frame(maxWidth: 460)
                .padding(.horizontal, bands.margin)
                .position(x: bands.size.width / 2, y: bands.y(0.905))
        }
    }

    private func landscape(_ bands: ScreenBands) -> some View {
        let columnWidth = bands.fullWidth * 0.30
        let width = min(columnWidth - bands.margin, (bands.size.height - Theme.s5) * 0.75)
        let consoleWidth = bands.fullWidth * 0.22
        return ZStack(alignment: .topLeading) {
            card(width: width, collectAnchor: UnitPoint(x: 3, y: 1))
                .position(x: bands.margin + width / 2, y: bands.size.height / 2)
            VStack(alignment: .trailing, spacing: Theme.s3) {
                Spacer(minLength: 0)
                toastSlot
                actions(landscape: true)
            }
            .frame(width: consoleWidth)
            .padding(.bottom, Theme.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, bands.margin)
        }
    }

    // MARK: Card

    private func card(width: CGFloat, collectAnchor: UnitPoint) -> some View {
        SpecimenCardView(specimen: specimen, thumbnail: collection.thumbnail(for: specimen),
                         style: .reveal, animateStamp: true)
            .frame(width: width)
            .overlay(alignment: .topLeading) { ribbon }
            .opacity(cardIn && !collecting ? 1 : 0)
            .offset(y: cardIn || reduceMotion ? 0 : -60)
            .rotationEffect(.degrees(cardIn || reduceMotion ? 0 : -3))
            .scaleEffect(collecting && !reduceMotion ? 0.3 : 1, anchor: collectAnchor)
    }

    @ViewBuilder
    private var ribbon: some View {
        if outcome.isNewBest {
            let upgraded = outcome.specimen.variant.isGolden || outcome.specimen.isPerfect
            Text(upgraded ? "NEW BEST" : "NEW ON THE SHELF")
                .font(Theme.micro)
                .tracking(Theme.microTracking)
                .foregroundStyle(Theme.graphite)
                .padding(.horizontal, Theme.s2)
                .padding(.vertical, 4)
                .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .topHighlight(cornerRadius: 6)
                .rotationEffect(.degrees(-5))
                .elevation(.e1)
                .offset(x: Theme.s3, y: -Theme.s2)
                .accessibilityHidden(true)
        }
    }

    // MARK: Toasts (one at a time)

    @ViewBuilder
    private var toastSlot: some View {
        let list = toasts
        ZStack {
            if toastIndex >= 0 && toastIndex < list.count && !collecting {
                let toast = list[toastIndex]
                ToastView(title: toast.title, detail: toast.detail, glyph: toast.glyph, accent: toast.accent)
                    .id(toast.id)
                    .transition(reduceMotion ? AnyTransition.opacity
                                             : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 52)
    }

    // MARK: Actions

    private func actions(landscape: Bool) -> some View {
        let layout = landscape ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Theme.s3))
                               : AnyLayout(HStackLayout(spacing: Theme.s3))
        return layout {
            Button(action: onAgain) {
                KeyLabel(title: "Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(KeycapStyle(kind: .secondary))
            .accessibilityHint("Press another \(outcome.specimen.kind.displayName).")

            Button {
                choosingShare = true
            } label: {
                KeyLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(KeycapStyle(kind: .secondary))
            .disabled(share.isExporting)

            Button(action: onNext) {
                KeyLabel(title: "Next", systemImage: "arrow.right", iconTrailing: true)
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: !landscape))
            .accessibilityHint(nextHint)
        }
        .disabled(collecting)
        .opacity(actionsIn && !collecting ? 1 : 0)
        .offset(y: actionsIn || reduceMotion ? 0 : 24)
    }

    private var nextHint: String {
        if let unlocked = outcome.newlyUnlocked.first {
            return "Puts the \(unlocked.displayName) on the anvil."
        }
        return "Collects this card and puts the next object on the anvil."
    }

    // MARK: Choreography (§6.8)

    private func choreograph() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(Theme.cardDrop(reduceMotion)) { cardIn = true }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(Theme.settle(reduceMotion)) { actionsIn = true }
            // Toasts, one at a time; the last one stays.
            let count = toasts.count
            for index in 0..<count {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 300 : 1_800))
                guard !Task.isCancelled, !collecting else { return }
                withAnimation(Theme.pop(reduceMotion)) { toastIndex = index }
                if index == 0 { UIFeel.success() }
            }
        }
        if UIAccessibility.isVoiceOverRunning {
            let announcement = ([specimen.accessibilitySentence] + toasts.map { "\($0.title.capitalized). \($0.detail)" })
                .joined(separator: " ")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
    }
}
