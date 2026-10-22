import SwiftUI
import UIKit

/// The Shelf (bible §5 screen 2, VISUAL-TARGET §6.9): a sticker album on dotted paper. Pressed objects show
/// their best card as a die-cut sticker (Golden > Perfect > newest); locked ones are embossed silhouettes in a
/// recessed well with a one-line hint. Tabs: Objects and Squished (the latest 200). Tap a sticker to put it
/// on the anvil. Settings opens from here.
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
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.top, 20)
                    .padding(.bottom, Theme.s3)
                tabs
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.bottom, Theme.s2)
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
        }
        // Settings stacks on the Shelf, so closing it comes back here (P2-11).
        .sheet(isPresented: $showSettings) {
            SettingsView(director: director)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
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

    private func objectsGrid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.s4), count: columns), spacing: Theme.s4) {
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

    // MARK: Squished

    @ViewBuilder
    private var squishedList: some View {
        let recent = Array(collection.specimens.prefix(200))
        if recent.isEmpty {
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
            .padding(.vertical, Theme.s7)
            .accessibilityElement(children: .combine)
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
                            .background(Theme.paper, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.paperEdge, lineWidth: 1))
                            .elevation(.e1)
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
            Group {
                if !unlocked {
                    Text(hint.uppercased())
                        .foregroundStyle(hintLit ? Theme.ink : Theme.inkSecondary)
                } else if let best {
                    Text(Self.bestLine(best))
                } else {
                    Text("NOT PRESSED YET")
                }
            }
            .font(Theme.micro)
            .tracking(Theme.microTracking * 0.6)
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
        }
        .accessibilityHidden(true)
    }

    /// "GOLDEN · PERFECT · №0042" under an unlocked slot.
    private static func bestLine(_ best: SpecimenRecord) -> String {
        var parts: [String] = []
        if best.variant.isGolden { parts.append("GOLDEN") }
        if best.isPerfect { parts.append("PERFECT") }
        parts.append(best.numberLabel)
        return parts.joined(separator: " · ")
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
        .background(Theme.paperWarm, in: shape)
        .topHighlight(cornerRadius: Theme.sectionRadius)
        .elevation(.e1)
        .accessibilityElement(children: .ignore)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear {
            withAnimation(Theme.row(index, reduceMotion)) { appeared = true }
        }
    }
}
