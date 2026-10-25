import SwiftUI

/// S8 Menu (UX-AUDIT-2 §4.2, EXPERIENCE-PLAN decision 8): the menu the founder looked for. A press-styled panel,
/// graphite with keycaps, in the half you touch: the base in tabletop (Apple's seated layout: controls at the bottom),
/// the trailing page in book pose, the lower part of the screen elsewhere. Any fold closes it.
enum MenuChoice: Hashable {
    case resume, objects, shelf, howTo, settings, about
}

struct MenuPanel: View {
    let collection: CollectionStore
    let onChoose: (MenuChoice) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sheetRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SQUISH")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Theme.yellow)
                        .accessibilityAddTraits(.isHeader)
                    Text("THE MUSEUM OF PRESSED THINGS")
                        .font(Theme.micro)
                        .tracking(Theme.microTracking)
                        .foregroundStyle(Theme.paper.opacity(0.7))
                }
                Spacer()
                Button {
                    onChoose(.resume)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(KeycapStyle(kind: .console, round: true))
                .accessibilityLabel("Close menu")
            }
            Button {
                onChoose(.resume)
            } label: {
                KeyLabel(title: "Resume", systemImage: "play.fill")
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true))
            .accessibilityHint("Back to the press.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.s2), GridItem(.flexible())], spacing: Theme.s2) {
                item(.objects, "Objects", "The museum", "square.stack.3d.up.fill")
                item(.shelf, "Shelf", collection.pressedKindsCount == 0 ? "Empty so far" : "\(collection.pressedKindsCount) pressed",
                     "square.grid.2x2.fill")
                item(.howTo, "How to press", "Show me again", "questionmark.circle.fill")
                item(.settings, "Settings", "Sound, haptics", "gearshape.fill")
            }
            Button {
                onChoose(.about)
            } label: {
                HStack(spacing: Theme.s2) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.yellow)
                    Text("About Squish")
                    Spacer(minLength: 0)
                    Text("NO ADS · NO TRACKING")
                        .font(Theme.micro)
                        .foregroundStyle(Theme.paper.opacity(0.6))
                }
            }
            .buttonStyle(KeycapStyle(kind: .console, fullWidth: true))
            .accessibilityHint("Credits, privacy, golden odds and the version.")
        }
        .padding(Theme.s4)
        .background {
            ZStack(alignment: .top) {
                shape.fill(LinearGradient(colors: [Theme.rgb(0x3A3D43), Theme.graphite], startPoint: .top, endPoint: .bottom))
                // Inside the rounded corners, so the stripe follows the panel's curve (HIG: concentric corners).
                MenuHazard()
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .padding(.horizontal, Theme.sheetRadius)
                    .padding(.top, 6)
                    .opacity(0.9)
            }
            .elevation(.e3)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: 520)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? Theme.fade : .spring(response: 0.32, dampingFraction: 0.8)) { appeared = true }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
        .accessibilityAddTraits(.isModal)
    }

    private func item(_ choice: MenuChoice, _ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Button {
            onChoose(choice)
        } label: {
            HStack(spacing: Theme.s2) {
                Image(systemName: symbol)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.yellow)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle.uppercased())
                        .font(Theme.micro)
                        .foregroundStyle(Theme.paper.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(KeycapStyle(kind: .console, fullWidth: true))
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

/// The hazard stripe along the menu panel's top edge.
private struct MenuHazard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.yellow))
            let period: CGFloat = 16
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height + period / 2, y: size.height))
                path.addLine(to: CGPoint(x: x + period / 2, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(Theme.graphite))
                x += period
            }
        }
        .accessibilityHidden(true)
    }
}
