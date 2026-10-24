import SwiftUI

/// S7's Achievements tab: all ten, earned and not. Earned ones sit on a yellow plate with their earned line; the rest
/// are embossed with a plain hint. The Secret stays a tease until it's earned.
struct AchievementsList: View {
    let collection: CollectionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let earned = collection.earnedAchievements
        // Earned first, then the rest in their usual order.
        let ordered = Achievement.allCases.filter { earned.contains($0) } + Achievement.allCases.filter { !earned.contains($0) }
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("\(earned.count)/\(Achievement.allCases.count) EARNED · GAME CENTER IS OPTIONAL".gluingDotSeparators)
                .font(Theme.label)
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityLabel("\(earned.count) of \(Achievement.allCases.count) achievements earned.")
            ForEach(Array(ordered.enumerated()), id: \.element) { index, achievement in
                AchievementRow(achievement: achievement, earned: earned.contains(achievement))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 8)
                    .animation(Theme.row(index, reduceMotion), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

private struct AchievementRow: View {
    let achievement: Achievement
    let earned: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        let hidden = achievement.isSecret && !earned
        HStack(spacing: Theme.s3) {
            ZStack {
                Circle()
                    .fill(earned ? Theme.yellow : Theme.paperShade.opacity(0.7))
                Circle()
                    .strokeBorder(earned ? Theme.yellowLip : Theme.paperEdge, lineWidth: 2)
                Image(systemName: hidden ? "questionmark" : achievement.symbolName)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(earned ? Theme.graphite : Theme.inkTertiary)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(hidden ? "???" : achievement.title)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(earned ? Theme.ink : Theme.inkSecondary)
                Text((earned ? achievement.detail : achievement.hint).keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if earned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.yellowLip)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.s4)
        .background { shape.fill(earned ? Theme.paper : Theme.paperWarm).elevation(earned ? .e1 : .e0) }
        .overlay {
            if !earned {
                shape.strokeBorder(Theme.paperEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hidden ? "Secret achievement" : achievement.title), \(earned ? "earned" : "not earned yet"). \(earned ? achievement.detail : achievement.hint)")
    }
}
