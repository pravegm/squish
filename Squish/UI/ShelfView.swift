import SwiftUI
import UIKit

/// The Shelf (bible §5 screen 2, VISUAL-TARGET §6.9): a sticker album on dotted paper. Pressed objects show
/// their best card as a die-cut sticker (Golden > Perfect > newest); locked ones are embossed silhouettes in a
/// recessed well with a one-line hint. Tabs: Objects and Squished (the latest 200). Tap a sticker to put it
/// on the anvil. Settings opens from here. On a tabletop Duo at `.large` the Objects tab splits at the crease: the
/// grid on the ram half, "Recently squished" prints on the anvil half (FOLD-REVIEW-7 N5).
struct ShelfView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case objects, squished
        var id: String { rawValue }
        var title: String {
            switch self {
            case .objects: "Objects"
            case .squished: "Squished"
            }
        }
    }

    let director: PressDirector
    /// Demo only: open this specimen's card once the sheet has settled.
    var demoDetail: UUID?
    /// Demo only: open Settings on top of the Shelf.
    var demoSettings = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// From RootView, forwarded to the stacked sheets so their `CreaseSafe` knows the pose (FOLD-REVIEW-6 N4).
    @Environment(\.windowIsLandscape) private var windowIsLandscape
    /// Tabletop Duo only (RootView): where the crease is, for the split Objects layout (FOLD-REVIEW-7 N5).
    @Environment(\.tabletopCreaseAboveSafeBottom) private var tabletopCreaseAboveSafeBottom
    @State private var tab: Tab
    @State private var detail: DetailRef?
    @State private var showSettings = false

    init(director: PressDirector, initialTab: Tab = .objects, demoDetail: UUID? = nil, demoSettings: Bool = false) {
        self.director = director
        self.demoDetail = demoDetail
        self.demoSettings = demoSettings
        _tab = State(initialValue: initialTab)
    }

    private var collection: CollectionStore { director.collection }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 600
            // Tabletop Duo at `.large`: the grid on the ram half, the latest prints on the anvil half (FOLD-REVIEW-7
            // N5). The header is a little tighter on both tabs then, so switching tabs never moves it.
            let creaseLine = ShelfTabletopLayout.creaseLine(sheet: proxy.size,
                                                            creaseAboveSafeBottom: tabletopCreaseAboveSafeBottom,
                                                            accessibilitySize: dynamicTypeSize.isAccessibilitySize)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.top, creaseLine == nil ? 20 : Theme.s4)
                    .padding(.bottom, creaseLine == nil ? Theme.s3 : Theme.s2)
                tabs
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.bottom, Theme.s2)
                if let creaseLine, tab == .objects {
                    tabletopObjects(creaseLine: creaseLine)
                } else {
                    ScrollView {
                        Group {
                            switch tab {
                            case .objects: objectsGrid(columns: dynamicTypeSize.isAccessibilitySize ? 1 : (wide ? 5 : 2))
                            case .squished: squishedList
                            }
                        }
                        .padding(.horizontal, wide ? 24 : 16)
                        .padding(.top, Theme.s3)
                        .padding(.bottom, Theme.s6)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .coordinateSpace(.named(Self.sheetSpace))
        }
        .sheet(item: $detail) { ref in
            CardDetailView(director: director, specimenID: ref.id, onPressAnother: { kind in
                detail = nil
                choose(kind)
            })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
                .creaseSafe()
                .environment(\.windowIsLandscape, windowIsLandscape)
        }
        // Settings stacks on the Shelf, so closing it comes back here (P2-11).
        .sheet(isPresented: $showSettings) {
            SettingsView(director: director)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
                .creaseSafe()
                .environment(\.windowIsLandscape, windowIsLandscape)
        }
        .task {
            guard demoDetail != nil || demoSettings else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if let demoDetail { detail = DetailRef(id: demoDetail) } else { showSettings = true }
        }
    }

    // MARK: Header (§6.7) and tabs (§6.9: two chips)

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Shelf")
                    .font(Theme.sheetTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(collection.pressedKindsCount)/\(ObjectKind.allCases.count) PRESSED · \(collection.totalPresses) SQUISHES")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel("\(collection.pressedKindsCount) of \(ObjectKind.allCases.count) objects pressed, \(collection.totalPresses) squishes in total")
                ProgressBar(fraction: Double(collection.pressedKindsCount) / Double(ObjectKind.allCases.count))
                    .frame(maxWidth: 220)
                    .accessibilityHidden(true)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .secondary, round: true))
            .accessibilityLabel("Settings")
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .secondary, round: true))
            .accessibilityLabel("Close shelf")
        }
    }

    private var tabs: some View {
        HStack(spacing: Theme.s2) {
            ForEach(Tab.allCases) { item in
                let selected = item == tab
                Button {
                    withAnimation(Theme.fade) { tab = item }
                } label: {
                    Text(item.title.uppercased())
                }
                .buttonStyle(KeycapStyle(kind: .chip, selected: selected))
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer()
        }
    }

    // MARK: Objects

    /// `cardWidth` fixes the columns (the tabletop split sizes the cards to fit the ram half); nil keeps them flexible.
    private func objectsGrid(columns: Int, cardWidth: CGFloat? = nil, rowSpacing: CGFloat = Theme.s4) -> some View {
        let item = cardWidth.map { GridItem(.fixed($0), spacing: Theme.s4) } ?? GridItem(.flexible(), spacing: Theme.s4)
        return LazyVGrid(columns: Array(repeating: item, count: columns), spacing: rowSpacing) {
            ForEach(Array(ObjectKind.allCases.enumerated()), id: \.element) { index, kind in
                let best = collection.best(for: kind)
                ShelfSlot(
                    kind: kind,
                    index: index,
                    unlocked: collection.isUnlocked(kind),
                    hint: collection.progressHint(for: kind),
                    best: best,
                    thumbnail: best.flatMap { collection.thumbnail(for: $0) },
                    isOnAnvil: kind == director.currentKind,
                    canChoose: director.canChooseObject,
                    onChoose: { choose(kind) },
                    onOpenCard: { card in detail = DetailRef(id: card.id) }
                )
            }
        }
    }

    private func choose(_ kind: ObjectKind) {
        director.choose(kind)
        dismiss()
    }

    // MARK: Tabletop split (FOLD-REVIEW-7 N5)

    private static let sheetSpace = "shelf.sheet"
    private static let tabletopColumns = 5
    private static let recentCount = 5

    /// The Objects tab on a tabletop Duo at `.large` (669 × ~900 pt, crease across the middle). The 5 × 2 grid
    /// filled only the ram half and left the anvil half blank, 55 % of the sheet. Now the grid is sized to end clear
    /// of the 40 pt crease band, and the anvil half holds the latest prints: the collection above, the evidence below.
    /// Nothing interactive sits within `creaseHalf + s2` of the crease line.
    private func tabletopObjects(creaseLine: CGFloat) -> some View {
        GeometryReader { area in
            let top = area.frame(in: .named(Self.sheetSpace)).minY
            let clearance = ScreenBands.creaseHalf + Theme.s2
            let gridHeight = max(0, creaseLine - clearance - top)
            let stripTop = max(gridHeight, creaseLine + clearance - top)
            let columns = Self.tabletopColumns
            let rows = (ObjectKind.allCases.count + columns - 1) / columns
            let card = ShelfTabletopLayout.cardWidth(width: area.size.width - 48,
                                                     height: gridHeight - Theme.s2 - Theme.s1,
                                                     columns: columns, rows: rows,
                                                     spacing: Theme.s4, rowSpacing: Theme.s3)
            VStack(spacing: 0) {
                // Still a scroll view: a larger (non-accessibility) type size may need a little more than the half.
                ScrollView {
                    objectsGrid(columns: columns, cardWidth: card, rowSpacing: Theme.s3)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, Theme.s2)
                        .padding(.bottom, Theme.s1)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: gridHeight)
                Color.clear
                    .frame(height: stripTop - gridHeight)
                    .accessibilityHidden(true)
                RecentlySquished(
                    specimens: Array(collection.specimens.prefix(Self.recentCount)),
                    totalCount: min(collection.specimens.count, 200), // the Squished tab's cap
                    thumbnail: { collection.thumbnail(for: $0) },
                    onOpen: { specimen in detail = DetailRef(id: specimen.id) },
                    onSeeAll: { withAnimation(Theme.fade) { tab = .squished } }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, Theme.s4)
                .frame(height: max(0, area.size.height - stripTop), alignment: .top)
            }
        }
    }

    // MARK: Squished

    @ViewBuilder
    private var squishedList: some View {
        let recent = Array(collection.specimens.prefix(200))
        if recent.isEmpty {
            NothingFlatYet()
                .padding(.vertical, Theme.s7)
        } else {
            LazyVStack(spacing: Theme.s3) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, specimen in
                    Button {
                        detail = DetailRef(id: specimen.id)
                    } label: {
                        SquishedRow(specimen: specimen, thumbnail: collection.thumbnail(for: specimen), index: index)
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityLabel(specimen.accessibilitySentence)
                    .accessibilityHint("Opens the card.")
                }
            }
        }
    }
}

struct DetailRef: Identifiable, Hashable {
    let id: UUID
}

/// "7/10 PRESSED" bar: 6 pt, paperShade track, yellow fill with a 1 pt yellowLip bottom.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.paperShade)
                Capsule()
                    .fill(Theme.yellow)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Theme.yellowLip).frame(height: 1).padding(.horizontal, 2)
                    }
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// Remembers which stickers have been placed, so only new ones "peel" in (§6.9).
@MainActor
private enum StickerLedger {
    private static let key = "squish.placedStickers"
    static func isNew(_ id: UUID) -> Bool {
        !(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }
    static func markPlaced(_ id: UUID) {
        var placed = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !placed.contains(id.uuidString) else { return }
        placed.append(id.uuidString)
        UserDefaults.standard.set(Array(placed.suffix(64)), forKey: key)
    }
}

// MARK: - Slot (3:4 well)

private struct ShelfSlot: View {
    let kind: ObjectKind
    let index: Int
    let unlocked: Bool
    /// Unlock hint with live progress ("SQUISH 3 DIFFERENT THINGS · 1/3").
    let hint: String
    let best: SpecimenRecord?
    let thumbnail: UIImage?
    let isOnAnvil: Bool
    let canChoose: Bool
    let onChoose: () -> Void
    let onOpenCard: (SpecimenRecord) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    @State private var peeling = false
    @State private var wiggle = 0.0
    @State private var hintLit = false

    var body: some View {
        ZStack {
            Well()
            VStack(spacing: Theme.s2) {
                art
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, Theme.s3)
                    .padding(.top, Theme.s3)
                caption
                    .padding(.horizontal, Theme.s2)
                Spacer(minLength: Theme.s2)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear(perform: enter)
    }

    @ViewBuilder
    private var art: some View {
        if unlocked {
            Button(action: onChoose) {
                Sticker(seed: best?.variant.seed ?? UInt64(index * 31), golden: best?.variant.isGolden == true) {
                    if let best {
                        SpecimenImage(specimen: best, thumbnail: thumbnail, cornerRadius: Theme.stickerRadius)
                    } else {
                        ObjectTile(kind: kind, cornerRadius: Theme.stickerRadius)
                    }
                }
                .scaleEffect(peeling ? 1.15 : 1)
                .rotationEffect(.degrees(peeling ? 8 : 0))
                .overlay(alignment: .bottomLeading) {
                    if isOnAnvil {
                        Text("ON THE ANVIL")
                            .font(Theme.micro)
                            .tracking(Theme.microTracking)
                            .foregroundStyle(Theme.graphite)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .rotationEffect(.degrees(-4))
                            .offset(x: -4, y: 6)
                    }
                }
            }
            .buttonStyle(TileButtonStyle())
            .disabled(!canChoose)
            .contextMenu {
                if let best {
                    Button("View Best Card", systemImage: "rectangle.portrait") { onOpenCard(best) }
                }
                Button("Put on the Anvil", systemImage: "arrow.down.to.line") { onChoose() }
            }
            .overlay(alignment: .topTrailing) {
                if let best {
                    Button {
                        onOpenCard(best)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Theme.graphite)
                            .frame(width: 28, height: 28)
                            .background { Circle().fill(Theme.paper).elevation(.e1) }
                            .overlay(Circle().strokeBorder(Theme.paperEdge, lineWidth: 1))
                            .frame(width: Theme.hit, height: Theme.hit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .offset(x: 10, y: -10)
                    .accessibilityHidden(true) // offered as a VoiceOver action on the slot instead
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(canChoose ? "Double-tap to put it on the anvil." : "")
            .accessibilityActions {
                if let best {
                    Button("View best card") { onOpenCard(best) }
                }
            }
        } else {
            // Locked slots answer back: a small wiggle and the hint lights up (P1-13).
            EmbossedSilhouette(kind: kind)
                .padding(Theme.s3)
                .rotationEffect(.degrees(wiggle))
                .contentShape(Rectangle())
                .onTapGesture(perform: nudgeLocked)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private func nudgeLocked() {
        UIFeel.tick()
        Task { @MainActor in
            if !reduceMotion {
                for angle in [3.0, -3.0, 3.0, -3.0, 0.0] {
                    withAnimation(.easeInOut(duration: 0.06)) { wiggle = angle }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
            withAnimation(Theme.fade) { hintLit = true }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(Theme.fade) { hintLit = false }
        }
    }

    private var caption: some View {
        VStack(spacing: 2) {
            Text(unlocked || !kind.isSecret ? kind.displayName : "???")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(unlocked ? Theme.ink : Theme.inkSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
            // Every card reserves two meta lines, so the art is the same size and the names line up whether the meta
            // takes one line or two (FOLD-REVIEW-7 N11: the Rubber Duck's name sat lower than its neighbours').
            ZStack(alignment: .top) {
                Text(verbatim: "\u{00A0}\n\u{00A0}")
                    .lineLimit(2)
                    .hidden()
                meta
            }
            .font(Theme.micro)
            .tracking(Theme.microTracking * 0.6)
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
        }
        .accessibilityHidden(true)
    }

    /// No line ever ends on a "·" (FOLD-REVIEW-7 N6: "PERFECT · / №0001").
    @ViewBuilder
    private var meta: some View {
        if !unlocked {
            // The separator is glued to both neighbours ("THINGS · 1/3" moves as one piece); three lines at most,
            // so a long progress hint wraps instead of truncating.
            Text(hint.uppercased().gluingDotSeparators)
                .foregroundStyle(hintLit ? Theme.ink : Theme.inkSecondary)
                .lineLimit(3)
        } else if let best {
            BestLine(parts: Self.bestParts(best))
        } else {
            Text("NOT PRESSED YET")
                .lineLimit(2)
        }
    }

    /// "GOLDEN · PERFECT · №0042" under an unlocked slot, as its pieces (the number last).
    private static func bestParts(_ best: SpecimenRecord) -> [String] {
        var parts: [String] = []
        if best.variant.isGolden { parts.append("GOLDEN") }
        if best.isPerfect { parts.append("PERFECT") }
        parts.append(best.numberLabel)
        return parts
    }

    private func enter() {
        let isNewSticker = best.map { StickerLedger.isNew($0.id) } ?? false
        if isNewSticker && !reduceMotion {
            peeling = true
            appeared = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150 + index * 40))
                withAnimation(Theme.stickerPeel(reduceMotion)) { peeling = false }
                UIFeel.tick()
            }
        } else {
            withAnimation(Theme.row(index, reduceMotion)) { appeared = true }
        }
        if let best { StickerLedger.markPlaced(best.id) }
    }

    private var accessibilityLabel: String {
        guard unlocked else {
            return kind.isSecret ? "Secret object, locked. \(hint)" : "\(kind.displayName), locked. \(hint)."
        }
        var text = kind.displayName
        if let best {
            let traits = best.traits.filter { $0.tone != .neutral }.map { $0.text.lowercased() }
            text += ". Best card number \(best.number)"
            if !traits.isEmpty { text += ", " + traits.joined(separator: ", ") }
        } else {
            text += ". Not pressed yet"
        }
        if isOnAnvil { text += ". On the anvil" }
        return text + "."
    }
}

/// A best card's meta under its sticker (FOLD-REVIEW-7 N6). The first variant that fits the card's width wins:
/// "PERFECT · №0001" on one line; else "PERFECT" / "№0001" (the flags glued together on line 1, the number on
/// line 2); else one piece per line. A wrapped line never ends on the separator.
private struct BestLine: View {
    let parts: [String]

    var body: some View {
        let oneLine = parts.joined(separator: " · ")
        if parts.count < 2 {
            Text(oneLine)
                .lineLimit(1)
        } else {
            ViewThatFits(in: .horizontal) {
                Text(oneLine)
                    .lineLimit(1)
                Text(ShelfMetaLines.twoLines(parts))
                    .lineLimit(2)
                Text(parts.joined(separator: "\n"))
                    .lineLimit(parts.count)
            }
        }
    }
}

/// Pure, so CollectionTests can check it.
enum ShelfMetaLines {
    /// Flags on line 1 (joined with a no-break " · ", so that line can't wrap on the separator), the № on line 2.
    static func twoLines(_ parts: [String]) -> String {
        guard let number = parts.last else { return "" }
        let flags = parts.dropLast()
        guard !flags.isEmpty else { return number }
        return flags.joined(separator: " · ").gluingDotSeparators + "\n" + number
    }
}

/// The recessed well each sticker sits in: paperShade 55% with a faked top inner shadow, radius 18.
private struct Well: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
        shape
            .fill(Theme.paperShade.opacity(0.55))
            .overlay {
                shape.strokeBorder(LinearGradient(stops: [
                    .init(color: Theme.shadowInk.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.3),
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

/// Album paper: grain plus a faint 8 pt dot grid (paperShade at 40%, 1 pt dots).
struct AlbumPage: View {
    var dots = true

    var body: some View {
        ZStack {
            PaperBackground()
            if dots {
                Canvas { context, size in
                    let spacing: CGFloat = 8
                    var path = Path()
                    var y: CGFloat = spacing / 2
                    while y < size.height {
                        var x: CGFloat = spacing / 2
                        while x < size.width {
                            path.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1))
                            x += spacing
                        }
                        y += spacing
                    }
                    context.fill(path, with: .color(Theme.paperShade.opacity(0.4)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Squished row

private struct SquishedRow: View {
    let specimen: SpecimenRecord
    let thumbnail: UIImage?
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        HStack(spacing: Theme.s3) {
            Sticker(seed: specimen.variant.seed, golden: specimen.variant.isGolden, tilted: false) {
                SpecimenImage(specimen: specimen, thumbnail: thumbnail, cornerRadius: 8)
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.s2) {
                    TintDot(kind: specimen.kind)
                    Text(specimen.kind.displayName)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Text("\(specimen.numberLabel) · \(specimen.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()).uppercased())")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                let traits = specimen.traits.map(\.text).joined(separator: " · ")
                Text(traits.isEmpty ? specimen.kind.breaksLine(fractureCount: specimen.fractureCount) : traits)
                    .font(Theme.micro)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(Theme.s4)
        .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        .topHighlight(cornerRadius: Theme.sectionRadius)
        .accessibilityElement(children: .ignore)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear {
            withAnimation(Theme.row(index, reduceMotion)) { appeared = true }
        }
    }
}

// MARK: - Empty state

/// "Nothing flat yet": the Squished tab and the tabletop "Recently squished" strip before the first press.
private struct NothingFlatYet: View {
    var body: some View {
        VStack(spacing: Theme.s3) {
            EmbossedSilhouette(kind: .bubbleWrap)
                .frame(width: 72, height: 72)
            Text("Nothing flat yet")
                .font(Theme.headline)
                .foregroundStyle(Theme.ink)
            Text("Every press you finish lands here, numbered and stamped.")
                .font(Theme.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recently squished (tabletop anvil half, FOLD-REVIEW-7 N5)

/// The anvil half of the tabletop Shelf: the newest print large, the four before it in a 2 × 2 beside it, sized to
/// fill the half. Empty places are bare wells, so the page reads as an album with room left. Tap a print for its card.
private struct RecentlySquished: View {
    /// Newest first, at most five.
    let specimens: [SpecimenRecord]
    let totalCount: Int
    let thumbnail: (SpecimenRecord) -> UIImage?
    let onOpen: (SpecimenRecord) -> Void
    let onSeeAll: () -> Void

    /// Room under each print for its name and number (two short lines).
    @ScaledMetric(relativeTo: .headline) private var captionHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Text("RECENTLY SQUISHED")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.s2)
                if !specimens.isEmpty {
                    Button(action: onSeeAll) {
                        HStack(spacing: Theme.s1) {
                            Text("SEE ALL \(totalCount)")
                            Image(systemName: "chevron.right")
                        }
                        .font(Theme.label)
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.graphite)
                        .frame(minHeight: Theme.hit)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all \(totalCount) squished")
                    .accessibilityHint("Opens the Squished tab.")
                }
            }
            .frame(minHeight: Theme.hit)

            if specimens.isEmpty {
                NothingFlatYet()
                    .frame(maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let fit = ShelfTabletopLayout.recent(width: proxy.size.width, height: proxy.size.height,
                                                        caption: captionHeight, spacing: Theme.s3)
                    HStack(alignment: .top, spacing: Theme.s3) {
                        printCell(at: 0, side: fit.hero, large: true)
                        VStack(spacing: Theme.s3) {
                            HStack(spacing: Theme.s3) {
                                printCell(at: 1, side: fit.small, large: false)
                                printCell(at: 2, side: fit.small, large: false)
                            }
                            HStack(spacing: Theme.s3) {
                                printCell(at: 3, side: fit.small, large: false)
                                printCell(at: 4, side: fit.small, large: false)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func printCell(at index: Int, side: CGFloat, large: Bool) -> some View {
        if index < specimens.count {
            let specimen = specimens[index]
            let nameStyle: Font.TextStyle = large ? .headline : .subheadline
            Button {
                onOpen(specimen)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Sticker(seed: specimen.variant.seed, golden: specimen.variant.isGolden) {
                        SpecimenImage(specimen: specimen, thumbnail: thumbnail(specimen),
                                      cornerRadius: large ? Theme.stickerRadius : 10)
                    }
                    .frame(width: side, height: side)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            TintDot(kind: specimen.kind, size: 8)
                            Text(specimen.kind.displayName)
                                .font(.system(nameStyle, design: .rounded, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        Text(Self.meta(specimen, large: large))
                            .font(Theme.micro)
                            .tracking(Theme.microTracking * 0.6)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: side, height: max(0, captionHeight - 6), alignment: .topLeading)
                }
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityLabel(specimen.accessibilitySentence)
            .accessibilityHint("Opens the card.")
        } else {
            VStack(spacing: 6) {
                Well()
                    .frame(width: side, height: side)
                Color.clear
                    .frame(width: side, height: max(0, captionHeight - 6))
            }
            .accessibilityHidden(true)
        }
    }

    /// One line, never wrapped: "№0007 · AT 72°", plus the day on the large print.
    private static func meta(_ specimen: SpecimenRecord, large: Bool) -> String {
        var parts = [specimen.numberLabel]
        if let gave = specimen.gaveAtTag { parts.append(gave) }
        if large { parts.append(specimen.date.formatted(.dateTime.day().month(.abbreviated)).uppercased()) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tabletop layout maths (pure; CollectionTests)

/// Sizes for the tabletop Duo Shelf (FOLD-REVIEW-7 N5).
enum ShelfTabletopLayout {
    /// The crease's centre line in the Shelf sheet's own safe-area coordinates, when the Objects tab should split
    /// around it; nil keeps the plain scrolling grid. Splits only on a tabletop Duo (`creaseAboveSafeBottom` known),
    /// on a wide sheet (the 5-column grid), when the sheet is clearly taller than wide (`.large`; at the 0.45 detent
    /// it is 669 × ~430 pt and sits wholly on the anvil half), with the crease near the sheet's middle, and never at
    /// accessibility type sizes (one column, which scrolls). Book pose and regular iPhones pass nil.
    static func creaseLine(sheet: CGSize, creaseAboveSafeBottom: CGFloat?, accessibilitySize: Bool) -> CGFloat? {
        guard let creaseAboveSafeBottom, !accessibilitySize,
              sheet.width > 600, sheet.height >= sheet.width * 1.2 else { return nil }
        let line = sheet.height - creaseAboveSafeBottom
        guard line >= sheet.height * 0.35, line <= sheet.height * 0.65 else { return nil }
        return line
    }

    /// A fixed sticker width for the Objects grid so `rows` rows of 3:4 slots fit in `height`, and never wider
    /// than `columns` flexible columns would be. Floored at 72 pt (the grid then scrolls a little).
    static func cardWidth(width: CGFloat, height: CGFloat, columns: Int, rows: Int,
                          spacing: CGFloat, rowSpacing: CGFloat, aspect: CGFloat = 0.75) -> CGFloat {
        let columns = CGFloat(max(1, columns)), rows = CGFloat(max(1, rows))
        let byWidth = (width - (columns - 1) * spacing) / columns
        let byHeight = (height - (rows - 1) * rowSpacing) / rows * aspect
        return max(72, min(byWidth, byHeight))
    }

    struct Recent: Equatable {
        /// The newest print's side.
        var hero: CGFloat
        /// Each of the four smaller prints' side.
        var small: CGFloat
    }

    /// The hero print plus a 2 × 2 of smaller ones, each with `caption` under it, filling `width` × `height`.
    /// The hero is as tall as the two small rows together (hero + caption = 2 × (small + caption) + spacing).
    static func recent(width: CGFloat, height: CGFloat, caption: CGFloat, spacing: CGFloat) -> Recent {
        let byWidth = (width - caption - 3 * spacing) / 4
        let byHeight = (height - spacing) / 2 - caption
        let small = max(0, min(byWidth, byHeight))
        return Recent(hero: 2 * small + caption + spacing, small: small)
    }
}
