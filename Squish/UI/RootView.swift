import StoreKit
import SwiftUI
import UIKit

/// The Press screen (bible §5 screen 1) and the host for every other screen.
/// Layout (VISUAL-TARGET §6.1): the 45–80% stage band is sacred. Idle chrome is only the console
/// (object chip + Shelf key) in the 86–95% band, shown while an object can be chosen; Settings lives in the Shelf.
/// During a press: zero UI except captions and the failure flash.
struct RootView: View {
    @State private var director = PressDirector()
    @State private var sheet: RootSheet?
    @State private var revealVisible = false
    @State private var collecting = false
    @State private var showSafetyHint = false
    @State private var shelfHop = 0
    @State private var accessiblePress = 0.0
    @State private var demoCover: CoverView.Content?
    @AppStorage("squish.askedForReview") private var askedForReview = false
    @AppStorage("squish.shelfDiscovered") private var shelfDiscovered = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    enum RootSheet: Identifiable, Equatable {
        case shelf(ShelfView.Tab, demoDetail: UUID?)
        case settings

        var id: String {
            switch self {
            case .shelf: "shelf"
            case .settings: "settings"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let bands = ScreenBands(proxy)
            ZStack {
                // Behind the RealityView: the current gel wall colour, so launch and rotation flashes match (§3.4).
                Theme.gel(for: director.currentKind, golden: director.variant.isGolden)
                    .ignoresSafeArea()
                    .animation(reduceMotion ? nil : Theme.gelCrossfade, value: director.currentKind)

                stage(height: bands.fullHeight)

                FailureFlash(count: director.failureFlashCount)

                PressHints(director: director)

                if director.settings.showCaptions && director.revealed == nil {
                    CaptionOverlay(caption: director.caption, kind: director.currentKind)
                }

                if director.canChooseObject && !isCoverUp {
                    console(bands)
                        .transition(.opacity)
                }

                if revealVisible, let outcome = director.revealed {
                    RevealCardView(
                        outcome: outcome,
                        collection: director.collection,
                        trace: director.trace(for: outcome.specimen),
                        collecting: collecting,
                        onNext: { collect { director.next() } },
                        onAgain: { collect { director.again() } }
                    )
                    .id(outcome.specimen.id)
                    .transition(.opacity)
                }

                if showSafetyHint && !isCoverUp {
                    SafetyHint()
                        .frame(maxWidth: 420)
                        .padding(.horizontal, bands.margin)
                        .position(x: bands.size.width / 2, y: bands.y(0.83))
                        .onTapGesture { showSafetyHint = false }
                        .transition(reduceMotion ? AnyTransition.opacity
                                                 : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                }

                if isCoverUp {
                    CoverView(
                        content: coverContent,
                        recent: Array(director.collection.specimens.prefix(3)),
                        currentKind: director.currentKind,
                        thumbnail: { director.collection.thumbnail(for: $0) },
                        reservesClockColumn: director.isShowingCover,
                        unlockedKinds: ObjectKind.allCases.filter { director.collection.isUnlocked($0) },
                        onQueue: { kind in
                            UIFeel.tick()
                            director.queue(kind)
                        },
                        showsSafetyLine: showSafetyHint
                    )
                    .transition(.opacity)
                }
            }
            .animation(Theme.fade, value: director.canChooseObject)
            .animation(Theme.fade, value: isCoverUp)
            .animation(Theme.pop(reduceMotion), value: showSafetyHint)
        }
        .modifier(HingeReader(
            onUpdate: { angle, closed in director.hingeUpdate(angle: angle, closed: closed) },
            onUnavailable: { director.hingeUnavailable() }
        ))
        .onAppear(perform: launch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.sceneBecameActive() }
        }
        .onChange(of: reduceMotion) { _, value in director.reduceMotion = value }
        .onChange(of: director.settings.hapticsLevel) { _, level in UIFeel.enabled = level != .off }
        .onChange(of: director.engine.phase) { _, phase in
            // Sheets never stay open during a press.
            if phase == .pressing || phase == .sealed { sheet = nil }
        }
        .onChange(of: director.isShowingCover) { _, covered in
            if covered { sheet = nil }
        }
        .task(id: director.revealed?.specimen.id) {
            await stageReveal()
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Stage

    private func stage(height: CGFloat) -> some View {
        PressSceneView(director: director)
            .ignoresSafeArea()
            .accessibilityIgnoresInvertColors(true)
            .gesture(touchPress(height: height), including: director.usesTouchPress ? .all : .none)
            .accessibilityElement()
            .accessibilityLabel("Press. \(director.currentKind.displayName) on the anvil.")
            .accessibilityValue(director.usesTouchPress ? "\(Int((accessiblePress * 100).rounded())) percent pressed" : "")
            .accessibilityHint(director.usesTouchPress
                               ? "Swipe up to press down, swipe down to ease off."
                               : "Fold your iPhone slowly to press.")
            .accessibilityAdjustableAction { direction in
                guard director.usesTouchPress, director.revealed == nil else { return }
                switch direction {
                case .increment: adjustAccessiblePress(by: 0.1)
                case .decrement: adjustAccessiblePress(by: -0.1)
                @unknown default: break
                }
            }
    }

    /// Pinch Press fallback: drag down anywhere to lower the ram.
    private func touchPress(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                director.virtualPress(max(0, value.translation.height) / max(height * 0.5, 1))
            }
            .onEnded { _ in
                director.virtualRelease()
            }
    }

    /// VoiceOver press: each swipe moves the ram 10%; reaching the bottom seals, and the press springs open after.
    private func adjustAccessiblePress(by delta: Double) {
        accessiblePress = min(max(accessiblePress + delta, 0), 1)
        director.virtualPress(accessiblePress)
        if accessiblePress >= 1 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                director.virtualRelease()
                accessiblePress = 0
            }
        } else if accessiblePress <= 0 {
            director.virtualRelease()
        }
    }

    // MARK: - Console (86–95%, or the right 22% column in landscape)

    @ViewBuilder
    private func console(_ bands: ScreenBands) -> some View {
        let chrome = IdleConsole(director: director, landscape: bands.isLandscape, hop: shelfHop,
                                 onShelf: { sheet = .shelf(.objects, demoDetail: nil) })
        if bands.isLandscape {
            chrome
                .frame(width: bands.fullWidth * 0.22, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, bands.margin)
                .padding(.bottom, Theme.s4)
        } else {
            chrome
                .padding(.horizontal, bands.margin)
                .position(x: bands.size.width / 2, y: bands.y(0.905))
        }
    }

    // MARK: - Sheets (§6.7)

    @ViewBuilder
    private func sheetContent(_ item: RootSheet) -> some View {
        switch item {
        case let .shelf(tab, demoDetail):
            ShelfView(director: director, initialTab: tab, demoDetail: demoDetail, onSettings: { sheet = .settings })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage() }
                .presentationContentInteraction(.scrolls)
                .sheetTypeCap()
        case .settings:
            SettingsView(director: director)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
        }
    }

    // MARK: - Reveal

    /// The card waits ~0.8 s so the ram lifts first (bible §3.1 beat 11).
    private func stageReveal() async {
        guard director.revealed != nil else {
            revealVisible = false
            collecting = false
            return
        }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, director.revealed != nil else { return }
        revealVisible = true
        accessiblePress = 0
        await askForReviewIfDue()
    }

    /// Once, after a reveal, after about 10 presses (bible §11). Never mid-press, never in demo runs.
    private func askForReviewIfDue() async {
        guard !askedForReview, director.completedPresses >= 10, DemoScenario.current == nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, director.revealed != nil else { return }
        askedForReview = true
        requestReview()
    }

    /// The card shrinks into the Shelf key over 0.45 s (§6.8), then the next object is placed.
    private func collect(_ action: @escaping () -> Void) {
        guard !collecting else { return }
        withAnimation(reduceMotion ? Theme.fade : .easeInOut(duration: 0.45)) { collecting = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 450))
            revealVisible = false
            collecting = false
            action()
            // After the second press the Shelf key hops once so people discover the collection (bible §3.2 step 8).
            if !shelfDiscovered && director.completedPresses >= 2 {
                shelfDiscovered = true
                try? await Task.sleep(for: .milliseconds(700))
                shelfHop += 1
            }
        }
    }

    // MARK: - Cover

    private var isCoverUp: Bool { director.isShowingCover || demoCover != nil }

    private var coverContent: CoverView.Content {
        if let demoCover { return demoCover }
        if director.engine.phase == .sealed, let result = director.engine.lastResult {
            // A provisional record, so the cover shows exactly the tonnage the card will.
            let provisional = SpecimenRecord(
                id: UUID(), number: director.completedPresses + 1, kind: result.kind, date: Date(),
                variant: PressVariant(kind: result.kind, seed: result.seed),
                fractureCount: result.fractureCount, maxCompression: result.maxCompression,
                failureAngle: result.failureAngle, duration: result.duration,
                isPerfect: result.isPerfect, wasSlammed: result.wasSlammed, reversals: result.reversals
            )
            return .sealed(kind: result.kind, tons: provisional.tons)
        }
        return .idle
    }

    // MARK: - Launch

    private func launch() {
        director.reduceMotion = reduceMotion
        UIFeel.enabled = director.settings.hapticsLevel != .off
        director.start()

        if let demo = DemoScenario.current {
            runDemo(demo)
            return
        }
        if !director.settings.hasSeenSafetyHint {
            director.settings.hasSeenSafetyHint = true
            director.settings.save()
            presentSafetyHint()
        }
    }

    private func presentSafetyHint() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            showSafetyHint = true
            try? await Task.sleep(for: .seconds(6))
            showSafetyHint = false
        }
    }

    /// UI demo keys for CI screenshots (see ci/scenarios.txt): `shelf[=squished]`, `detail`, `settings`, `cover[=sealed]`.
    private func runDemo(_ demo: DemoScenario) {
        if demo.name == "launch" { presentSafetyHint() }
        if demo.has("cover") {
            demoCover = demo.string("cover") == "sealed" ? .sealed(kind: demo.object ?? .rubberDuck, tons: 48) : .idle
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            if demo.has("settings") {
                sheet = .settings
            } else if demo.has("detail") {
                let best = ObjectKind.allCases.compactMap { director.collection.best(for: $0) }
                    .first { $0.variant.isGolden } ?? director.collection.specimens.first
                sheet = .shelf(.objects, demoDetail: best?.id)
            } else if demo.has("shelf") {
                sheet = .shelf(demo.string("shelf") == "squished" ? .squished : .objects, demoDetail: nil)
            }
        }
    }
}
