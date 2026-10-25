import StoreKit
import SwiftUI
import UIKit

/// The Press screen and the host for every other screen (design/EXPERIENCE-PLAN.md "Screens", UX-AUDIT-2 §4):
/// - S0 the launch beat (`LaunchBeat`), held until the hinge has reported so a Duo never flashes the P-48;
/// - S1 the first-run lesson (`FoldLessonCard`) and the coach line for the first 5 presses (`CoachLine`);
/// - S2 the press room: the stage, and the console with ☰ Menu, the object tray, Shelf and ⚙ (`PressConsole`), plus the
///   "Next unlock" line;
/// - S3 the Tray (`TrayView`), S7 the Shelf, S9 Settings, S10 Help, About: sheets;
/// - S5/S6 the reveal ceremony (`RevealCardView`) and "Up next" after a collect;
/// - S8 the Menu panel (`MenuPanel`), in the half you touch;
/// - S10 the automatic pause (`PauseCard`);
/// - the cover display's states (`CoverView`).
/// Layout (VISUAL-TARGET §6.1): the 45–80% stage band stays clear on the P-48. On the Duo, watching content sits on the
/// lid (top / leading page) and controls on the base (bottom / trailing page), never on the crease.
struct RootView: View {
    @State private var director = PressDirector()
    @State private var tips = TipCenter()
    @State private var sheet: RootSheet?
    /// The sheet was opened from the outer display: closing the phone doesn't dismiss it.
    @State private var sheetFromCover = false
    @State private var menuOpen = false
    @State private var revealVisible = false
    @State private var collecting = false
    @State private var flyTarget: CGPoint?
    @State private var shelfKeyFrame: CGRect = .zero
    @State private var shelfHop = 0
    @State private var shelfBump = 0
    @State private var trayPulse = 0
    @State private var accessibleStep = 0
    @State private var touchedOnce = false
    @State private var uiCollected = false
    @State private var pendingCoach: String?
    @State private var demoCover: CoverView.Content?
    /// The window's orientation, for `CreaseSafe` inside sheets (FOLD-REVIEW-6 N4: a sheet's own aspect isn't the pose).
    @State private var windowLandscape: Bool?
    /// Tabletop Duo: the crease's height above the safe bottom, for the Shelf's split layout (FOLD-REVIEW-7 N5).
    @State private var tabletopCrease: CGFloat?
    /// The Shelf sheet's detent, reset each time it opens (`shelfOpeningDetent`).
    @State private var shelfDetent: PresentationDetent = .medium
    /// S0.
    @State private var launchPhase: LaunchPhase = .apart
    /// The hinge reader has answered at all (a reading, or "no hinge here").
    @State private var hingeReported = false
    /// The full canvas, to guess a foldable before its hinge reports (the Duo's displays are ~0.7 wide, iPhones ~0.46).
    @State private var canvasSize: CGSize = .zero
    /// S1 replayed from the Menu or Settings: teaches the next press, then turns itself off.
    @State private var lessonReplay = false
    @State private var soundCheckPlayed = false
    /// The last reveal's outcome, for S6's "Up next" / "New in the museum".
    @State private var lastReveal: RecordOutcome?
    /// S10: the automatic pause.
    @State private var pause: PauseState?
    @State private var pauseTask: Task<Void, Never>?
    @AppStorage("squish.askedForReview") private var askedForReview = false
    @AppStorage("squish.shelfDiscovered") private var shelfDiscovered = false
    /// Remembered once a hinge has ever reported, so a Duo never gets non-Duo copy (UX-REVIEW-1 P1-16).
    @AppStorage("squish.hasHinge") private var hasHinge = false
    @AppStorage(LessonMemory.doneKey) private var lessonDone = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    enum RootSheet: Identifiable, Equatable {
        case shelf(ShelfView.Tab, demoDetail: UUID?)
        case tray
        case settings
        case help
        case about

        var id: String {
            switch self {
            case .shelf: "shelf"
            case .tray: "tray"
            case .settings: "settings"
            case .help: "help"
            case .about: "about"
            }
        }
    }

    struct PauseState: Equatable {
        var tons: Int
        var angle: Double
    }

    /// A half-closed press that hasn't moved for this long pauses (S10).
    static let pauseAfter: Double = 20

    var body: some View {
        GeometryReader { proxy in
            let bands = ScreenBands(proxy, hinge: director.hingeAvailable || hasHinge)
            ZStack {
                // Behind the RealityView: the current gel wall colour, so launch and rotation flashes match (§3.4).
                Theme.gel(for: director.currentKind, golden: director.variant.isGolden)
                    .ignoresSafeArea()
                    .animation(reduceMotion ? nil : Theme.gelCrossfade, value: director.currentKind)

                if stageMounted {
                    stage(height: bands.fullHeight)
                }

                FailureFlash(count: director.failureFlashCount)

                if !director.usesFoldPress && launchPhase >= .opening {
                    // P-48 touch press: the ram handle on the crosshead, at rest (FOLD-REVIEW-5 N6, screenshots.md P1).
                    PinchHandle(director: director,
                                suppressed: revealVisible || collecting || isCoverUp || bands.isLandscape || sheet != nil
                                    || lessonVisible || menuOpen)
                }

                if showsCaptions && director.revealed == nil {
                    CaptionOverlay(caption: director.caption, kind: director.currentKind)
                }

                Group {
                    pressRoom(bands)
                    revealLayer(bands)
                    watchHalf(bands)
                }

                if isCoverUp {
                    cover
                        .transition(.opacity)
                }

                if menuOpen {
                    menuLayer(bands)
                        .transition(.opacity)
                }

                if launchPhase < .done {
                    LaunchBeat(phase: launchPhase)
                        .zIndex(10)
                }
            }
            .animation(Theme.fade, value: director.canChooseObject)
            .animation(Theme.fade, value: isCoverUp)
            .animation(Theme.fade, value: menuOpen)
            .animation(Theme.fade, value: lessonVisible)
            .animation(Theme.fade, value: pause)
            .animation(Theme.pop(reduceMotion), value: tips.current)
            .onChange(of: bands.isLandscape, initial: true) { _, landscape in
                windowLandscape = landscape
            }
            .onChange(of: bands.tabletopCreaseAboveSafeBottom, initial: true) { _, crease in
                tabletopCrease = crease
            }
            .onChange(of: CGSize(width: bands.fullWidth, height: bands.fullHeight), initial: true) { _, size in
                canvasSize = size
                director.setWindowSize(size)   // the outer display by size, not by hinge status
            }
        }
        .modifier(HingeReader(
            onUpdate: { angle, closed in
                hingeReported = true
                director.hingeUpdate(angle: angle, closed: closed)
            },
            onUnavailable: {
                hingeReported = true
                director.hingeUnavailable()
            }
        ))
        .onAppear(perform: launch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.sceneBecameActive() }
            // S10: the app went away mid-press. The press keeps its damage; the card says how to carry on.
            if phase == .background, director.engine.phase == .pressing { pauseNow() }
        }
        .onChange(of: reduceMotion) { _, value in director.reduceMotion = value }
        .onChange(of: director.settings.hapticsLevel) { _, level in UIFeel.enabled = level != .off }
        .onChange(of: pressedPastContact) { _, pressed in
            // Sheets close only once the ram really touches the object, not on a 4° wobble (P2-10).
            if pressed && !sheetFromCover { sheet = nil }
            if pressed { menuOpen = false }
        }
        .onChange(of: director.engine.phase) { _, phase in
            if phase == .pressing { pressStarted() }
            if phase != .pressing { clearPause() }
        }
        .onChange(of: director.engine.isHolding) { _, holding in
            holdingChanged(holding)
        }
        .onChange(of: director.isShowingCover) { _, covered in
            if covered && !sheetFromCover { sheet = nil }
        }
        .onChange(of: sheet) { _, value in
            if value == nil { sheetFromCover = false }
        }
        .onChange(of: director.hingeAvailable) { _, available in
            if available { hingeArrived() }
        }
        .onChange(of: needsOpening) { _, needed in
            if needed { scheduleOpenUp() } else { tips.dismiss(.openUp) }
        }
        .onChange(of: director.coachHint) { _, hint in
            guard let hint else { return }
            pendingCoach = hint.text
            showPendingTips()
        }
        .onChange(of: director.canChooseObject) { _, canChoose in
            if canChoose { showPendingTips() }
        }
        .onChange(of: lessonVisible) { _, visible in
            if visible { playSoundCheck() }
        }
        .onChange(of: director.revealed?.specimen.id) { old, new in
            if new != nil {
                lastReveal = director.revealed
                // The first reveal completes the first-run lesson.
                if !isDemo && !lessonDone { lessonDone = true }
            }
            // Collected by the hinge (fold or close) rather than a keycap.
            if old != nil && new == nil {
                if uiCollected { uiCollected = false } else { didCollect() }
            }
        }
        .task(id: director.revealed?.specimen.id) {
            await stageReveal()
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        // ICON DEMO: `-squishDemo icon` shows only the app icon art, a full-width square centred on black, for
        // ci/screenshots.sh to crop into AppIcon-1024.png. DEBUG only (DemoScenario.current is nil in release).
        .overlay {
            if DemoScenario.current?.has("icon") == true {
                GeometryReader { geo in
                    ZStack {
                        Color.black
                        AppIconArt()
                            .frame(width: geo.size.width, height: geo.size.width)
                    }
                }
                .ignoresSafeArea()
            }
        }
        // ICON DEMO end
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Stage

    /// S0: the stage mounts once the press type is known. A hinge reading mounts the Fold Press at once; the P-48 waits
    /// for the launch beat to give up on a hinge, so a Duo never draws it.
    private var stageMounted: Bool {
        isDemo || launchPhase >= .opening || director.hingeAvailable
    }

    /// iPhone Duo: the two halves of the screen are the press (FOLD-PRESS.md). Every other iPhone: the P-48 machine.
    @ViewBuilder private var stageContent: some View {
        if director.usesFoldPress {
            FoldPressView(director: director)
        } else {
            PressSceneView(director: director)
        }
    }

    private func stage(height: CGFloat) -> some View {
        stageContent
            .ignoresSafeArea()
            .accessibilityIgnoresInvertColors(true)
            .gesture(touchPress(height: height), including: director.usesTouchPress ? .all : .none)
            .accessibilityElement()
            .accessibilityLabel("Press. \(director.currentKind.displayName) on the anvil.")
            .accessibilityValue(pressValue)
            .accessibilityHint(director.usesTouchPress
                               ? "Swipe up to press down, swipe down to ease off."
                               : "Fold your iPhone closed, slowly, to press. Open it again to see what's left.")
            .accessibilityAdjustableAction { direction in
                guard director.usesTouchPress, director.revealed == nil else { return }
                switch direction {
                case .increment: adjustAccessiblePress(by: 1)
                case .decrement: adjustAccessiblePress(by: -1)
                @unknown default: break
                }
            }
    }

    /// Pinch Press (UX-REVIEW-1 P0-2): the drag is scaled to the room left below the finger, so a press can
    /// always finish wherever it starts — including on the object itself. The end of the room is just past seal.
    /// A drag that is turning the object (`PressScene.isInspecting`) never presses.
    private func touchPress(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !director.scene.isInspecting, !menuOpen else { return }
                if !touchedOnce {
                    touchedOnce = true
                    tips.dismiss(.dragDown)
                }
                let room = min(max(height * 0.93 - value.startLocation.y, 160), height * 0.5)
                let sealFraction = (180 - director.engine.config.endAngle) / 180 + 0.04
                director.virtualPress(max(0, value.translation.height) / room * sealFraction)
            }
            .onEnded { _ in
                director.virtualRelease()
            }
    }

    /// VoiceOver value from the real press depth (P1-11).
    private var pressValue: String {
        let engine = director.engine
        switch engine.phase {
        case .sealed, .revealing: return "Sealed"
        case .idle, .armed, .pressing: break
        }
        if engine.measuredDepth < engine.mapping.contactT {
            return engine.measuredDepth > 0.01 ? "Approaching" : "Ready"
        }
        let compression = engine.measuredCompression
        return compression < 0.02 ? "Touching" : "\(Int((compression * 100).rounded())) percent squished"
    }

    /// VoiceOver press: step 1 is contact, then each swipe adds 12.5% compression; step 9 seals.
    private func adjustAccessiblePress(by delta: Int) {
        let config = director.engine.mapping
        accessibleStep = min(max(accessibleStep + delta, 0), 9)
        guard accessibleStep > 0 else {
            director.virtualRelease()
            return
        }
        let compression = Double(accessibleStep - 1) / 8
        let depth = min(1, config.contactT + (1 - config.contactT) * compression)
        let angle = PressMapping.angle(forDepth: depth, start: config.armAngleMax, config: config)
        director.virtualPress((180 - angle) / 180 + (accessibleStep == 9 ? 0.04 : 0))
        if accessibleStep >= 9 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                director.virtualRelease()
                accessibleStep = 0
            }
        }
    }

    private var pressedPastContact: Bool {
        director.engine.measuredDepth >= director.engine.mapping.contactT || director.engine.phase == .sealed
    }

    private var showsCaptions: Bool {
        director.settings.showCaptions || director.completedPresses < CoachLine.presses || lessonReplay
    }

    // MARK: - S2 Press room: console and next-unlock line

    @ViewBuilder
    private func pressRoom(_ bands: ScreenBands) -> some View {
        if (director.canChooseObject || collecting || consoleHoldsChip) && !isCoverUp && launchPhase >= .opening {
            console(bands)
                .transition(.opacity)
            if director.canChooseObject && !collecting && director.revealed == nil, let spot = nextUnlockSpot(bands) {
                NextUnlockLine(collection: director.collection)
                    .frame(maxWidth: spot.width)
                    .position(x: spot.midX, y: spot.midY)
                    .transition(.opacity)
            }
        }
    }

    private func console(_ bands: ScreenBands) -> some View {
        let frame = consoleFrame(bands)
        let landscape = bands.isLandscape && !director.usesFoldPress
        return PressConsole(director: director, landscape: landscape, hop: shelfHop, bump: shelfBump,
                            trayPulse: trayPulse, shelfOnly: collecting,
                            pressing: !director.canChooseObject && !collecting,
                            onMenu: { menuOpen = true },
                            onTray: { presentSheet(.tray) },
                            onShelf: openShelf,
                            onSettings: { presentSheet(.settings) },
                            onShelfFrame: { shelfKeyFrame = $0 },
                            width: frame.width)
            .position(x: frame.midX, y: frame.midY)
    }

    /// Tabletop (and non-folding phones): a fixed-width console on the bottom plate's outer edge, far from the crease.
    /// Book pose: inside the bezel's console band under the right thumb. Fold Press: one row inside the 62 pt console
    /// band, leaving the pilot lamp at its far end uncovered (FOLD-REVIEW-1 #5).
    private func consoleFrame(_ bands: ScreenBands) -> CGRect {
        if director.usesFoldPress {
            let band = bands.local(bands.foldLayout.consoleBand)
            let width = min(band.width - Theme.s3 * 2 - 36, 455)
            return CGRect(x: band.minX + Theme.s3, y: band.midY - 22, width: width, height: 44)
        }
        if bands.isLandscape {
            let width = max(200, bands.fullWidth * 0.24)
            let height: CGFloat = 44 * 3 + Theme.s3 * 2
            return CGRect(x: bands.size.width - bands.margin - width, y: bands.size.height - Theme.s4 - height,
                          width: width, height: height)
        }
        let width = min(bands.size.width - bands.margin * 2, 460)
        return CGRect(x: bands.size.width / 2 - width / 2, y: bands.y(0.905) - 22, width: width, height: 44)
    }

    /// Just above the console: on the anvil field (tabletop), the trailing page (book), the 86% line elsewhere.
    private func nextUnlockSpot(_ bands: ScreenBands) -> CGRect? {
        let frame = consoleFrame(bands)
        if director.usesFoldPress {
            let band = bands.local(bands.foldLayout.consoleBand)
            return CGRect(x: frame.minX, y: band.minY - 28, width: frame.width, height: 24)
        }
        if bands.isLandscape { return nil }
        return CGRect(x: frame.minX, y: bands.y(0.862) - 12, width: frame.width, height: 24)
    }

    /// Fold Press, mid-press (FOLD-REVIEW-3 N16): the console stays, dimmed and inert, so the band isn't empty graphite
    /// and every pressing frame says what's on the anvil. Not during the reveal (its own keys own the band) and never on
    /// the P-48, whose press keeps zero chrome.
    private var consoleHoldsChip: Bool {
        director.usesFoldPress && director.revealed == nil && !revealVisible
    }

    private func openShelf() {
        shelfDiscovered = true
        presentSheet(.shelf(.objects, demoDetail: nil))
    }

    // MARK: - The watching half: lesson, coach, pause, tips

    /// S1 is on: the first run (until the first reveal) or a replay. Never in CI demo runs.
    private var lessonActive: Bool {
        guard !isDemo || DemoScenario.current?.has("lesson") == true else { return false }
        return lessonReplay || (!lessonDone && director.completedPresses == 0)
    }

    private var lessonVisible: Bool {
        lessonActive && launchPhase == .done && director.canChooseObject && !isCoverUp && sheet == nil && !menuOpen
            && pause == nil
    }

    private var soundLine: String {
        let settings = director.settings
        if !settings.soundEnabled { return "Sound is off. Turn it on in Settings." }
        if settings.playSoundInSilentMode { return "Sound plays even on Silent. Change it in Settings." }
        return "Squish follows your Silent switch. Change it in Settings."
    }

    @ViewBuilder
    private func watchHalf(_ bands: ScreenBands) -> some View {
        let card = lessonCardFrame(bands)
        if lessonVisible {
            FoldLessonCard(engine: director.engine, hinge: director.usesFoldPress,
                           book: bands.isLandscape, soundLine: soundLine,
                           onHelp: { presentSheet(.help) })
                .frame(width: card.width)
                .position(x: card.midX, y: card.midY)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        } else if let pause, !isCoverUp, director.revealed == nil {
            PauseCard(tons: pause.tons, touch: director.usesTouchPress,
                      onResume: { clearPause() },
                      onHelp: { clearPause(); presentSheet(.help) },
                      onMenu: { clearPause(); menuOpen = true })
                .frame(width: card.width)
                .position(x: card.midX, y: card.midY)
                .transition(.opacity)
        }
        if showsTipSlot {
            let slot = tipPlacement(bands)
            Group {
                if let tip = tips.current {
                    TipToast(tip: tip, compact: director.usesFoldPress)
                        .onTapGesture { tips.dismissAll() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .id(tip.id)
                } else if launchPhase == .done {
                    PressCoachSlot(director: director, pressIndex: lessonReplay ? 0 : director.completedPresses,
                                   showsIdleLine: !lessonVisible && pause == nil, compact: director.usesFoldPress)
                }
            }
            .frame(width: slot.width)
            .position(x: slot.midX, y: slot.midY)
        }
    }

    /// The lesson and pause cards: centred on the lid's field (tabletop), the leading page (book), the top band (P-48).
    private func lessonCardFrame(_ bands: ScreenBands) -> CGRect {
        if director.usesFoldPress {
            let field = bands.local(bands.foldLayout.platenField)
            let width = min(field.width - Theme.s5 * 2, 460)
            return CGRect(x: field.midX - width / 2, y: field.minY + Theme.s4, width: width,
                          height: max(0, field.height - Theme.s4 * 2 - FoldLayout.toastHeight))
        }
        if bands.isLandscape {
            let width = min(bands.fullWidth * 0.5 - ScreenBands.creaseHalf - bands.margin * 2, 440)
            return CGRect(x: bands.margin, y: bands.size.height * 0.2, width: width, height: bands.size.height * 0.5)
        }
        let width = min(bands.size.width - bands.margin * 2, 440)
        return CGRect(x: bands.size.width / 2 - width / 2, y: bands.y(0.07), width: width, height: bands.y(0.36) - bands.y(0.07))
    }

    private var showsTipSlot: Bool {
        !isCoverUp && !revealVisible && director.revealed == nil && !menuOpen && launchPhase >= .opening
    }

    /// Where one-time tips and the coach line go: the Fold Press toast slot (off the crown strip and the plates,
    /// FOLD-REVIEW-4 F4), the 80–86% band in portrait, or the right half in landscape (clear of the crease).
    private func tipPlacement(_ bands: ScreenBands) -> CGRect {
        if director.usesFoldPress {
            return bands.foldToastSlot
        }
        if bands.isLandscape {
            let width = max(300, bands.fullWidth * 0.5 - ScreenBands.creaseHalf - bands.margin * 2)
            let center = CGPoint(x: bands.x(0.75), y: bands.size.height * 0.62)
            return CGRect(x: center.x - width / 2, y: center.y - 26, width: width, height: 52)
        }
        let width = min(420, bands.size.width - bands.margin * 2)
        return CGRect(x: bands.size.width / 2 - width / 2, y: bands.y(0.83) - 26, width: width, height: 52)
    }

    // MARK: - S8 Menu

    private func menuLayer(_ bands: ScreenBands) -> some View {
        let region = menuRegion(bands)
        return ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { menuOpen = false }
                .accessibilityHidden(true)
            MenuPanel(collection: director.collection, onChoose: chooseFromMenu)
                .frame(width: region.width)
                .frame(maxHeight: region.height, alignment: .bottom)
                .position(x: region.midX, y: region.midY)
        }
        .zIndex(5)
    }

    /// The half you touch (HIG seated layout: controls at the bottom; book: the trailing page).
    private func menuRegion(_ bands: ScreenBands) -> CGRect {
        // Clear of the hazard jaws and the display's rounded corners.
        let margin = Theme.s5
        if isCoverUp {
            let width = min(bands.size.width - margin * 2, 460)
            return CGRect(x: bands.size.width / 2 - width / 2, y: margin, width: width, height: bands.size.height - margin * 2)
        }
        if let crease = bands.crease {
            if bands.isLandscape {
                let x = crease.maxX + margin
                return CGRect(x: x, y: margin, width: min(bands.size.width - x - margin, 520),
                              height: bands.size.height - margin * 2)
            }
            let y = crease.maxY + margin
            let width = min(bands.size.width - margin * 2, 520)
            return CGRect(x: bands.size.width / 2 - width / 2, y: y, width: width, height: bands.size.height - y - margin)
        }
        let width = min(bands.size.width - margin * 2, 520)
        let top = bands.size.height * 0.3
        return CGRect(x: bands.size.width / 2 - width / 2, y: top, width: width, height: bands.size.height - top - margin)
    }

    private func chooseFromMenu(_ choice: MenuChoice) {
        UIFeel.tick()
        menuOpen = false
        switch choice {
        case .resume: break
        case .objects: presentSheet(.tray)
        case .shelf: openShelf()
        case .howTo: replayIntro()
        case .settings: presentSheet(.settings)
        case .about: presentSheet(.about)
        }
    }

    // MARK: - Sheets

    /// Every sheet goes through here: the Shelf always opens at `shelfOpeningDetent`, and a sheet opened on the cover
    /// stays when the phone is opened or shut.
    private func presentSheet(_ item: RootSheet) {
        menuOpen = false
        if case .shelf = item { shelfDetent = shelfOpeningDetent }
        sheetFromCover = isCoverUp
        sheet = item
    }

    /// The Shelf's short detent. On a Duo the medium detent's top edge would sit in the crease (P1-19).
    private var shelfShortDetent: PresentationDetent { hasHinge ? .fraction(0.45) : .medium }

    /// Duo: full height (FOLD-REVIEW-6 N4, FOLD-REVIEW-7 N5). Other iPhones keep opening at medium, over the P-48.
    private var shelfOpeningDetent: PresentationDetent { hasHinge ? .large : .medium }

    /// The Tray: full height on a Duo (a medium detent's edge would sit in the crease), medium first elsewhere.
    private var trayDetents: Set<PresentationDetent> {
        hasHinge ? [.large] : [.medium, .large]
    }

    @ViewBuilder
    private func sheetContent(_ item: RootSheet) -> some View {
        switch item {
        case let .shelf(tab, demoDetail):
            ShelfView(director: director, initialTab: tab, demoDetail: demoDetail)
                .presentationDetents([shelfShortDetent, .large], selection: $shelfDetent)
                .presentationContentInteraction(.scrolls)
                .modifier(SheetChrome(dots: true, windowLandscape: windowLandscape, tabletopCrease: tabletopCrease))
        case .tray:
            TrayView(director: director)
                .presentationDetents(trayDetents)
                .presentationContentInteraction(.scrolls)
                .modifier(SheetChrome(dots: true, windowLandscape: windowLandscape, tabletopCrease: tabletopCrease))
        case .settings:
            SettingsView(director: director, onReplayIntro: replayIntro)
                .presentationDetents([.large])
                .modifier(SheetChrome(dots: false, windowLandscape: windowLandscape, tabletopCrease: tabletopCrease))
        case .help:
            HelpView(onReplayIntro: replayIntro)
                .presentationDetents([.large])
                .modifier(SheetChrome(dots: false, windowLandscape: windowLandscape, tabletopCrease: tabletopCrease))
        case .about:
            AboutView(director: director)
                .presentationDetents([.large])
                .modifier(SheetChrome(dots: false, windowLandscape: windowLandscape, tabletopCrease: tabletopCrease))
        }
    }

    // MARK: - S1 lesson

    /// Menu → How to press, Settings → Replay intro: the lesson again, on Bubble Wrap.
    private func replayIntro() {
        sheet = nil
        menuOpen = false
        clearPause()
        lessonReplay = true
        soundCheckPlayed = false
        if director.canChooseObject && director.currentKind != .bubbleWrap {
            director.choose(.bubbleWrap)
        }
        if lessonVisible { playSoundCheck() }
    }

    /// S1's sound check: a soft two-note chime as the lesson card comes up, once per lesson ("Hear that?").
    private func playSoundCheck() {
        guard !soundCheckPlayed else { return }
        soundCheckPlayed = true
        director.playUICue(BrandCues.tick(BrandCues.pentatonic[4], gain: 1.4)
            .adding(BrandCues.tick(BrandCues.pentatonic[7], gain: 1.4).delayed(by: 0.12)), light: true)
    }

    // MARK: - S10 pause

    private func holdingChanged(_ holding: Bool) {
        pauseTask?.cancel()
        pauseTask = nil
        guard director.engine.phase == .pressing else { return }
        if holding {
            pauseTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.pauseAfter))
                guard !Task.isCancelled, director.engine.phase == .pressing, director.engine.isHolding,
                      director.revealed == nil else { return }
                pauseNow()
            }
        } else if let pause, abs(director.engine.angle - pause.angle) > 3 {
            clearPause()
        }
    }

    private func pauseNow() {
        guard !isDemo else { return }
        pause = PauseState(tons: liveTons, angle: director.engine.angle)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement,
                                 argument: "Paused at \(liveTons) tons. Close to keep going, or open it up to ease off.")
        }
    }

    private func clearPause() {
        pauseTask?.cancel()
        pauseTask = nil
        pause = nil
    }

    /// The gauge's reading right now, on the same scale as the card's tonnage.
    private var liveTons: Int {
        Int(director.engine.liveTons.rounded())   // the force on the press (`Tonnage`), as the gauge shows it
    }

    // MARK: - Reveal (S5) and collect (S6)

    @ViewBuilder
    private func revealLayer(_ bands: ScreenBands) -> some View {
        if revealVisible, let outcome = director.revealed {
            RevealCardView(
                outcome: outcome,
                collection: director.collection,
                trace: director.trace(for: outcome.specimen),
                collecting: collecting,
                flyTarget: flyTarget,
                hinge: bands.hinge,
                foldPress: director.usesFoldPress,
                revealLit: { await director.fold.revealLit() },
                playReplay: { director.fold.playBreakReplay(speed: RevealCeremony.replaySpeed) },
                stopReplay: { director.fold.stopBreakReplay() },
                foldToKeep: director.foldToKeepReady,
                firstReveal: director.completedPresses <= 1,
                playCue: { director.playUICue($0, light: true) },
                onKeep: { collect { director.next() } },
                onAgain: { collect { director.again() } },
                onSettings: { presentSheet(.settings) }
            )
            .id(outcome.specimen.id)
            .transition(.opacity)
        }
    }

    /// The card waits ~0.8 s so the ram lifts first (0.3 s under Reduce Motion), and for the specimen photo,
    /// so the peak moment never swaps a placeholder for the real thing (P1-1).
    private func stageReveal() async {
        guard let outcome = director.revealed else {
            revealVisible = false
            collecting = false
            flyTarget = nil
            return
        }
        if director.usesFoldPress {
            // FOLD-REVIEW-7 N10, reveal on relight: the stage has drawn the diptych by the time the inner display
            // lights; the ceremony's keys go up at once, and the rest waits for `revealLit` (RevealCardView).
            guard !Task.isCancelled, director.revealed != nil else { return }
            tips.dismissAll()
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { revealVisible = true }
            accessibleStep = 0
            await askForReviewIfDue()
            return
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 800))
        var waited = 0
        while director.collection.specimen(withID: outcome.specimen.id)?.thumbnailFile == nil && waited < 700 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            waited += 50
        }
        guard !Task.isCancelled, director.revealed != nil else { return }
        tips.dismissAll()
        revealVisible = true
        accessibleStep = 0
        await askForReviewIfDue()
    }

    /// Once, after a reveal, after about 10 presses (bible §11). Never mid-press, never in demo runs.
    private func askForReviewIfDue() async {
        guard !askedForReview, director.completedPresses >= 10, DemoScenario.current == nil else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled, director.revealed != nil else { return }
        askedForReview = true
        requestReview()
    }

    /// Collect (P1-2): the reveal actions fade, the Shelf key appears on the console, the card flies into it,
    /// the key sinks in and its count rolls, then the next object is placed.
    private func collect(_ action: @escaping () -> Void) {
        guard !collecting else { return }
        withAnimation(.easeOut(duration: 0.15)) { collecting = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90)) // let the Shelf key lay out
            let target = CGPoint(x: shelfKeyFrame.midX, y: shelfKeyFrame.midY)
            withAnimation(reduceMotion ? Theme.fade : .spring(response: 0.38, dampingFraction: 0.72)) { flyTarget = target }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 230 : 400))
            uiCollected = true
            revealVisible = false
            flyTarget = nil
            action()
            collecting = false
            didCollect()
        }
    }

    /// After any collect (keycap or hinge): land the card in the Shelf, then S6's "Up next" for the object that's
    /// now on the anvil (a fresh unlock says so).
    private func didCollect() {
        shelfBump += 1
        trayPulse += 1
        lessonReplay = false
        GameCenter.shared.firstRunFinished()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        // After the second press the Shelf key hops once so people discover the collection (bible §3.2 step 8).
        if !shelfDiscovered && director.completedPresses >= 2 {
            shelfDiscovered = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                shelfHop += 1
            }
        }
        if !isDemo {
            let kind = director.currentKind
            let isNew = lastReveal?.newlyUnlocked.contains(kind) ?? false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard director.canChooseObject, director.currentKind == kind else { return }
                tips.show(tips.upNext(kind, isNew: isNew))
            }
        }
        showPendingTips()
    }

    // MARK: - Tips (UX-REVIEW-1 §6.3)

    private var isDemo: Bool { DemoScenario.current != nil }

    /// Hinge present, idle because it's folded below the arming angle (P1-15). The lesson card says it itself.
    private var needsOpening: Bool {
        director.hingeAvailable && !director.usesTouchPress && !director.isShowingCover && director.revealed == nil
            && director.engine.phase == .idle && director.engine.angle < director.engine.config.armAngleMin
            && !lessonActive
    }

    private func scheduleOpenUp() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if needsOpening { tips.show(tips.openUp(book: windowLandscape == true)) }
        }
    }

    private func hingeArrived() {
        hasHinge = true
        tips.dismiss(.dragDown)
        // The safety line lives on the lesson card's footer now (UX-AUDIT-2 §4.2 S1), not as the app's first words.
        if lessonActive, !director.settings.hasSeenSafetyHint {
            director.settings.hasSeenSafetyHint = true
            director.settings.save()
        }
    }

    private func pressStarted() {
        tips.dismissAll()
        menuOpen = false
    }

    /// Coaching waits for a calm, idle moment (never during a press or the reveal).
    private func showPendingTips() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2_900))
            guard director.canChooseObject, !revealVisible, tips.current == nil else { return }
            if let line = pendingCoach {
                pendingCoach = nil
                tips.show(tips.coach(line))
            }
        }
    }

    /// Touch press, first run: if nothing has been touched after 20 s, one "DRAG DOWN" tip until the first touch.
    private func scheduleDragHint(after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard director.usesTouchPress, !hasHinge, !touchedOnce, director.completedPresses == 0,
                  director.revealed == nil, tips.current == nil, !lessonVisible else { return }
            if !isDemo { TipCenter.markShown(.dragDown) }
            tips.show(tips.dragDown())
        }
    }

    // MARK: - Cover

    private var isCoverUp: Bool { director.isShowingCover || demoCover != nil }

    private var cover: some View {
        let content = coverContent
        let lobby = content == .idle
        return CoverView(
            content: content,
            recent: Array(director.collection.specimens.prefix(3)),
            currentKind: director.currentKind,
            thumbnail: { director.collection.thumbnail(for: $0) },
            reservesClockColumn: director.isShowingCover,
            unlockedKinds: ObjectKind.museumOrder.filter { director.collection.isUnlocked($0) },
            onQueue: coverQueue,
            showsSafetyLine: content == .firstRun,
            pressedCount: director.collection.pressedKindsCount,
            onShelf: lobby ? { openShelf() } : nil,
            onMenu: lobby ? { menuOpen = true } : nil,
            onSettings: lobby ? { presentSheet(.settings) } : nil,
            soundLine: soundLine
        )
    }

    /// Cover chips queue the next object; hidden while a reveal is still pending (no dead chips, P0-4).
    private var coverQueue: ((ObjectKind) -> Void)? {
        guard director.revealed == nil else { return nil }
        let director = director
        return { kind in
            UIFeel.tick()
            director.queue(kind)
        }
    }

    private var coverContent: CoverView.Content {
        if let demoCover { return demoCover }
        let engine = director.engine
        if let revealed = director.revealed { return .releasing(tons: revealed.specimen.tons) }
        switch engine.phase {
        case .revealing:
            return .releasing(tons: provisionalTons ?? liveTons)
        case .sealed:
            if let tons = provisionalTons { return .sealed(kind: director.currentKind, tons: tons) }
            return .sealing(tons: liveTons)
        case .pressing:
            // Closed mid-press without sealing (Press without folding, or a hesitant close): C3 when paused.
            return pause != nil || director.settings.pressWithoutFolding ? .paused(tons: liveTons) : .sealing(tons: liveTons)
        case .idle, .armed:
            break
        }
        if !isDemo && !lessonDone && director.completedPresses == 0 { return .firstRun }
        return .idle
    }

    /// The tonnage the card will show for the sealed press (a provisional record, so cover and card agree).
    private var provisionalTons: Int? {
        guard let result = director.engine.lastResult else { return nil }
        let provisional = SpecimenRecord(
            id: UUID(), number: director.completedPresses + 1, kind: result.kind, date: Date(),
            variant: PressVariant(kind: result.kind, seed: result.seed),
            fractureCount: result.fractureCount, maxCompression: result.maxCompression,
            failureAngle: result.failureAngle, duration: result.duration,
            isPerfect: result.isPerfect, wasSlammed: result.wasSlammed, reversals: result.reversals
        )
        return provisional.tons
    }

    // MARK: - Launch (S0)

    private func launch() {
        director.reduceMotion = reduceMotion
        UIFeel.enabled = director.settings.hapticsLevel != .off
        director.start()

        if let demo = DemoScenario.current {
            launchPhase = .done
            runDemo(demo)
            return
        }
        if director.hingeAvailable { hingeArrived() }
        Task { @MainActor in await runLaunchBeat() }
        // The crosshead's Pinch Press handle says "drag down" from the first frame (`PinchHandle`), so the toast is
        // only a late fallback for someone who still hasn't touched anything.
        if !TipCenter.hasShown(.dragDown) { scheduleDragHint(after: .seconds(20)) }
    }

    /// Looks like a foldable before any hinge reading: the Duo's displays are about 0.7 wide to tall, iPhones ~0.46.
    private var looksFoldable: Bool {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return hasHinge }
        let aspect = min(canvasSize.width, canvasSize.height) / max(canvasSize.width, canvasSize.height)
        return hasHinge || aspect > 0.6
    }

    /// Hiss, slam (with the clunk), hold for the hinge, part. About 1.2 s when the hinge answers at once.
    private func runLaunchBeat() async {
        director.playUICue(BrandCues.releaseSigh, light: true)
        if reduceMotion {
            launchPhase = .closed
        } else {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeIn(duration: 0.26)) { launchPhase = .closed }
            try? await Task.sleep(for: .milliseconds(260))
        }
        director.playUICue(BrandCues.bottomOut)
        try? await Task.sleep(for: .milliseconds(520))
        // Wait for the first hinge reading, so a Duo never flashes the P-48. A phone that says "no hinge" goes at once;
        // one that looks foldable waits a little longer for a reading that a still Duo may be slow to send.
        let deadline = CACurrentMediaTime() + (looksFoldable ? 2.5 : 0.8)
        while !director.hingeAvailable && CACurrentMediaTime() < deadline {
            if hingeReported && !looksFoldable { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeIn(duration: 0.34)) { launchPhase = .opening }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 260 : 360))
        launchPhase = .done
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// UI demo keys for CI screenshots (see ci/scenarios.txt): `shelf[=squished|achievements]`, `detail`, `settings`,
    /// `cover[=sealed|sealing|releasing|paused|firstrun]`, and (this round) `menu`, `tray`, `help`, `about`, `lesson`.
    private func runDemo(_ demo: DemoScenario) {
        if demo.has("cover") {
            let kind = demo.object ?? .rubberDuck
            switch demo.string("cover") {
            case "sealed": demoCover = .sealed(kind: kind, tons: 48)
            case "sealing": demoCover = .sealing(tons: 31)
            case "releasing": demoCover = .releasing(tons: 48)
            case "paused": demoCover = .paused(tons: 38)
            case "firstrun": demoCover = .firstRun
            default: demoCover = .idle
            }
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            if demo.has("settings") {
                presentSheet(.settings)
            } else if demo.has("detail") {
                let best = ObjectKind.allCases.compactMap { director.collection.best(for: $0) }
                    .first { $0.variant.isGolden } ?? director.collection.specimens.first
                presentSheet(.shelf(.objects, demoDetail: best?.id))
            } else if demo.has("shelf") {
                let tab: ShelfView.Tab
                switch demo.string("shelf") {
                case "squished": tab = .squished
                case "achievements": tab = .achievements
                default: tab = .objects
                }
                presentSheet(.shelf(tab, demoDetail: nil))
            } else if demo.has("menu") {
                menuOpen = true
            } else if demo.has("tray") {
                presentSheet(.tray)
            } else if demo.has("help") {
                presentSheet(.help)
            } else if demo.has("about") {
                presentSheet(.about)
            }
        }
    }
}

/// The shared sheet chrome: grabber, radius, album paper, the type cap, crease safety and the window's pose.
private struct SheetChrome: ViewModifier {
    let dots: Bool
    let windowLandscape: Bool?
    let tabletopCrease: CGFloat?

    func body(content: Content) -> some View {
        content
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.sheetRadius)
            .presentationBackground { AlbumPage(dots: dots) }
            .sheetTypeCap()
            // No `creaseSafe()`: in book pose each of these sheets lays itself out as a two-page spread (`BookSpread`)
            // instead of leaving the leading page blank.
            .environment(\.windowIsLandscape, windowLandscape)
            .environment(\.tabletopCreaseAboveSafeBottom, tabletopCrease)
    }
}

/// The coach line (first 5 presses) in the toast slot: reads the engine itself, so only this redraws at hinge rate.
private struct PressCoachSlot: View {
    let director: PressDirector
    let pressIndex: Int
    /// Idle, presses 2–3: one gentle "Close it slowly to press" line.
    var showsIdleLine = true
    var compact = true
    /// When the hand came to rest after the break (nil while it hasn't).
    @State private var restingSince: Date?

    /// The object has given: its failure, or every fracture for things that never fail (bubble wrap).
    private var broken: Bool {
        let engine = director.engine
        if let threshold = engine.failureThreshold { return engine.measuredCompression >= threshold }
        return !engine.thresholds.isEmpty && engine.firedCount >= engine.thresholds.count
    }

    private var restingAfterBreak: Bool { broken && director.engine.isHolding }

    var body: some View {
        // Ticks only so "Shut it all the way" can appear once the hand has rested 1.5 s past the break.
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            slot(now: context.date)
        }
        .onChange(of: restingAfterBreak, initial: true) { _, resting in
            restingSince = resting ? Date() : nil
        }
    }

    @ViewBuilder
    private func slot(now: Date) -> some View {
        let engine = director.engine
        let stalled = restingSince.map { now.timeIntervalSince($0) >= CoachLine.stallAfterBreak } ?? false
        let line = CoachLine.line(phase: engine.phase, compression: engine.measuredCompression,
                                  depth: engine.measuredDepth, contactDepth: engine.mapping.contactT,
                                  broken: broken, stalledAfterBreak: stalled,
                                  closingSpeed: engine.closingSpeed, slamSpeed: engine.config.slamSpeed,
                                  touch: director.usesTouchPress, pressIndex: pressIndex)
        ZStack {
            if let line {
                CoachLineView(line: line, compact: compact)
                    .id(line.title)
                    .transition(.opacity)
            } else if showsIdleLine, pressIndex >= 1, pressIndex < 3, director.canChooseObject {
                CoachLineView(line: CoachLine(title: "READY",
                                              detail: director.usesTouchPress ? "Drag down slowly to press." : "Close it slowly to press.",
                                              symbol: "tortoise.fill"),
                              compact: compact)
                    .transition(.opacity)
            }
        }
        .animation(Theme.fade, value: line)
    }
}
