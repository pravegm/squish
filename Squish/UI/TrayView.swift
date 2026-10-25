import SwiftUI
import UIKit

/// S3 The Tray: the object picker as "The Museum of Pressed Things" (EXPERIENCE-PLAN decision 7, UX-AUDIT-2 §4.2).
/// Three wings that escalate soft → crunchy → tough, and a vault for the steel ball. Every tile promises something:
/// a picture, the name, a verb, a stiffness bar, its three goals (Perfect / Surprise / Golden) and, when locked, plain
/// progress. Tap a tile and it goes on the anvil.
struct TrayView: View {
    let director: PressDirector

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var collection: CollectionStore { director.collection }

    @Environment(\.windowIsLandscape) private var windowIsLandscape
    @AppStorage("squish.hasHinge") private var hasHinge = false

    var body: some View {
        if SheetPose.isBook(hasHinge: hasHinge, windowIsLandscape: windowIsLandscape) {
            // Book pose: the anvil and the legend on the leading page, the wings on the trailing one.
            BookSpread {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    onTheAnvil
                    GoalLegend()
                    closingLine
                }
            } right: {
                VStack(alignment: .leading, spacing: Theme.s5) {
                    ForEach(MuseumWing.allCases) { wing in
                        wingSection(wing, columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
                    }
                }
            }
            .onAppear { appeared = true }
        } else {
            singleColumn
        }
    }

    private var closingLine: some View {
        Text("Every object breaks its own way. Some hide things. One in fifty is golden.".keepingLastWordsTogether)
            .font(Theme.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var singleColumn: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > 560
            // An even number of columns (HIG for grids near the fold); one at accessibility sizes.
            let columns = dynamicTypeSize.isAccessibilitySize ? 1 : (wide ? 4 : 2)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.top, 20)
                    .padding(.bottom, Theme.s3)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s5) {
                        onTheAnvil
                        GoalLegend()
                        ForEach(MuseumWing.allCases) { wing in
                            wingSection(wing, columns: columns)
                        }
                        closingLine
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, wide ? 24 : 16)
                    .padding(.bottom, Theme.s6)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("The Museum of Pressed Things")
                    .font(Theme.sheetTitle)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("\(collection.pressedKindsCount)/\(ObjectKind.allCases.count) PRESSED · \(collection.unlockedCount) OPEN")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel("\(collection.pressedKindsCount) of \(ObjectKind.allCases.count) pressed, \(collection.unlockedCount) open")
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .secondary, round: true))
            .accessibilityLabel("Close the museum")
        }
    }

    /// The object on the anvil, large, with its promise and its museum label.
    private var onTheAnvil: some View {
        let kind = director.currentKind
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return HStack(alignment: .center, spacing: Theme.s4) {
            ObjectTile(kind: kind, cornerRadius: Theme.stickerRadius, golden: director.variant.isGolden)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("ON THE ANVIL")
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.inkSecondary)
                Text(kind.displayName)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                Text(kind.behaviour.keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("“\(kind.flavourLines.first ?? "")”")
                    .font(.system(.footnote, design: .serif).italic())
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.s4)
        .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        .topHighlight(cornerRadius: Theme.cardRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: Wings

    private func wingSection(_ wing: MuseumWing, columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: Theme.s3), count: columns)
        return VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(wing.plate)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.graphite)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(wing == .vault ? Theme.steel.opacity(0.35) : Theme.yellowSoft))
                Text(wing.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if wing != .vault {
                    Text("\(collection.pressedCount(in: wing))/\(wing.kinds.count)")
                        .font(Theme.label)
                        .foregroundStyle(collection.isWingComplete(wing) ? Theme.ink : Theme.inkSecondary)
                    if collection.isWingComplete(wing) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.yellowLip)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(wing.tagline)
                .font(Theme.footnote)
                .foregroundStyle(Theme.inkSecondary)
            LazyVGrid(columns: grid, spacing: Theme.s3) {
                ForEach(Array(wing.kinds.enumerated()), id: \.element) { index, kind in
                    MuseumTile(kind: kind,
                               unlocked: collection.isUnlocked(kind),
                               onAnvil: kind == director.currentKind,
                               goals: collection.goals(for: kind),
                               progress: collection.unlockProgress(for: kind),
                               canChoose: director.canChooseObject,
                               onChoose: { choose(kind) })
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 8)
                        .animation(Theme.row(index, reduceMotion), value: appeared)
                }
            }
        }
    }

    private func choose(_ kind: ObjectKind) {
        UIFeel.tick()
        director.choose(kind)
        dismiss()
    }
}

/// One exhibit: picture, name, verb, stiffness, goals, and plain unlock progress when locked.
struct MuseumTile: View {
    let kind: ObjectKind
    let unlocked: Bool
    let onAnvil: Bool
    let goals: CollectionStore.Goals
    let progress: CollectionStore.UnlockProgress?
    let canChoose: Bool
    let onChoose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = 0.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
        Button {
            if unlocked { onChoose() } else { nudge() }
        } label: {
            VStack(alignment: .leading, spacing: Theme.s2) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if unlocked {
                            ObjectTile(kind: kind, cornerRadius: Theme.stickerRadius)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous)
                                    .fill(Theme.paperShade.opacity(0.6))
                                EmbossedSilhouette(kind: kind).padding(Theme.s4)
                                Image(systemName: "lock.fill")
                                    .font(.system(.footnote, weight: .bold))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    .padding(Theme.s2)
                            }
                        }
                    }
                    .aspectRatio(1.35, contentMode: .fit)
                    .rotationEffect(.degrees(wiggle))
                    if onAnvil {
                        Text("ON THE ANVIL")
                            .font(Theme.micro)
                            .tracking(Theme.microTracking * 0.6)
                            .foregroundStyle(Theme.graphite)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.yellow).elevation(.e1))
                            .rotationEffect(.degrees(-4))
                            .offset(x: -4, y: -6)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.s1) {
                    Text(unlocked || !kind.isSecret ? kind.displayName : "???")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(unlocked ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                HStack(spacing: Theme.s2) {
                    Text((unlocked || !kind.isSecret ? kind.verb : "???").uppercased())
                        .font(Theme.micro)
                        .tracking(Theme.microTracking * 0.6)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Theme.graphite)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.tint(for: kind).opacity(unlocked ? 0.35 : 0.15)))
                    Spacer(minLength: 0)
                    StiffnessBar(level: kind.stiffness, offTheScale: kind.isOffTheScale && unlocked)
                }
                if unlocked {
                    GoalSlots(goals: goals)
                } else if let progress {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.line.capitalizedFirstLetter.gluingDotSeparators)
                            .font(Theme.micro)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.paperShade)
                                Capsule().fill(Theme.yellow)
                                    .frame(width: max(4, bar.size.width * progress.fraction))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(Theme.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(unlocked ? Theme.paper : Theme.paperWarm).elevation(unlocked ? .e1 : .e0) }
            .overlay {
                if onAnvil { shape.strokeBorder(Theme.graphite, lineWidth: 2) }
            }
        }
        .buttonStyle(TileButtonStyle())
        .disabled(unlocked && !canChoose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(unlocked ? (canChoose ? "Puts it on the anvil." : "") : "Locked.")
        .accessibilityAddTraits(onAnvil ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let name = unlocked || !kind.isSecret ? kind.displayName : "Secret object"
        guard unlocked else {
            var text = "\(name), locked."
            if let progress {
                let done = min(progress.done, progress.total)
                text += " \(progress.task.capitalizedFirstLetter), \(done) of \(progress.total)."
            }
            return text
        }
        var parts = ["\(name). \(kind.verb). Stiffness \(kind.stiffness) of 5."]
        parts.append(goals.perfect ? "Perfect found." : "No Perfect yet.")
        if let surprise = goals.surprise { parts.append(surprise ? "Surprise found." : "A surprise hides in some.") }
        if let golden = goals.golden { parts.append(golden ? "Golden found." : "Golden not found yet.") }
        if onAnvil { parts.append("On the anvil.") }
        return parts.joined(separator: " ")
    }

    private func nudge() {
        UIFeel.tick()
        guard !reduceMotion else { return }
        Task { @MainActor in
            for angle in [3.0, -3.0, 3.0, -3.0, 0.0] {
                withAnimation(.easeInOut(duration: 0.06)) { wiggle = angle }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}

/// Five pips: how hard it fights back. The steel ball fills them red and reads MAX.
struct StiffnessBar: View {
    let level: Int
    var offTheScale = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(pip <= level ? (offTheScale ? Theme.stamp : Theme.graphite) : Theme.paperShade)
                    .frame(width: 5, height: 4 + CGFloat(pip) * 1.6)
            }
            if offTheScale {
                Text("MAX")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.stamp)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The key to the goal slots, once above the wings: "✦ Perfect · 🎁 Surprise · 👑 Golden".
struct GoalLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.s3) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each object has three goals: a Perfect Squish, a hidden surprise, and a golden one.")
    }

    @ViewBuilder
    private var items: some View {
        item("sparkles", "Perfect squish")
        item("gift.fill", "Surprise inside")
        item("crown.fill", "Golden, 1 in 50")
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.graphite)
            Text(text.uppercased())
                .font(Theme.micro)
                .tracking(Theme.microTracking * 0.5)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize()
        }
    }
}

/// Perfect ◇ · Surprise ◇ · Golden ◇, filled when found; a dash where the object can't have one.
struct GoalSlots: View {
    let goals: CollectionStore.Goals

    var body: some View {
        HStack(spacing: Theme.s2) {
            slot("sparkles", "PERFECT", found: goals.perfect, tint: Theme.yellow)
            slot("gift.fill", "SURPRISE", found: goals.surprise, tint: Theme.rgb(0x9CC2EA))
            slot("crown.fill", "GOLDEN", found: goals.golden, tint: Theme.gold)
        }
        .accessibilityHidden(true)
    }

    /// Icons only (the legend above the wings names them), so a narrow tile never cuts a word off.
    @ViewBuilder
    private func slot(_ symbol: String, _ title: String, found: Bool?, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: found == nil ? "minus" : symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(found == true ? Theme.graphite : Theme.inkTertiary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        .background(shape.fill(found == true ? tint.opacity(0.55) : Color.clear))
        .overlay(shape.strokeBorder(found == true ? tint : Theme.paperEdge,
                                    style: StrokeStyle(lineWidth: 1, dash: found == true ? [] : [2, 2])))
        .opacity(found == nil ? 0.5 : 1)
    }
}
