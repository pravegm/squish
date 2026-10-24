import SwiftUI

/// S0 (UX-AUDIT-2 §4.2, EXPERIENCE-PLAN "Screens"): a 1.2 s brand beat on every cold launch. The two plates slam
/// together with a hiss-clunk, SQUISH stamps on the lid, then they part on the press room. RootView drives `phase`
/// and holds it at `.closed` until the hinge has reported (or clearly won't), so a Duo never flashes the P-48.
enum LaunchPhase: Int, Comparable {
    /// The plates hang open: the very first frame.
    case apart
    /// Slammed shut, wordmark stamped. Held here while the app waits for the first hinge reading.
    case closed
    /// Parting on the press room.
    case opening
    /// Gone.
    case done

    static func < (lhs: LaunchPhase, rhs: LaunchPhase) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct LaunchBeat: View {
    let phase: LaunchPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Wider than tall is book pose: the plates are the two pages, the seam the vertical crease.
            let book = size.width > size.height
            let half = book ? size.width / 2 : size.height / 2
            let gap: CGFloat = reduceMotion ? 0 : (phase == .apart ? half * 0.2 : 0)
            let away: CGFloat = reduceMotion ? 0 : (phase >= .opening ? half + 30 : 0)
            let shift = gap + away
            let plateSize = book ? CGSize(width: size.width / 2, height: size.height)
                                 : CGSize(width: size.width, height: size.height / 2)
            ZStack {
                // The dark inside of the press, seen through the gap.
                Theme.rgb(0x111214)
                    .opacity(phase >= .opening ? 0 : 1)
                LaunchPlate(lid: true, book: book, stamped: phase >= .closed)
                    .frame(width: plateSize.width, height: plateSize.height)
                    .position(x: book ? size.width * 0.25 - shift : size.width / 2,
                              y: book ? size.height / 2 : size.height * 0.25 - shift)
                LaunchPlate(lid: false, book: book, stamped: phase >= .closed)
                    .frame(width: plateSize.width, height: plateSize.height)
                    .position(x: book ? size.width * 0.75 + shift : size.width / 2,
                              y: book ? size.height / 2 : size.height * 0.75 + shift)
            }
            .opacity(reduceMotion && phase >= .opening ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(phase < .opening)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Squish")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One plate of the launch press: graphite steel, a hazard band on the edge that meets the other plate, four bolts,
/// and (on the lid) the SQUISH wordmark that stamps in at the slam.
private struct LaunchPlate: View {
    let lid: Bool
    let book: Bool
    let stamped: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which edge of this plate meets the other one.
    private var seam: Alignment {
        if book { return lid ? .trailing : .leading }
        return lid ? .bottom : .top
    }

    var body: some View {
        ZStack(alignment: seam) {
            LinearGradient(colors: lid ? [Theme.rgb(0x3A3D43), Theme.rgb(0x2B2D31)]
                                       : [Theme.rgb(0x2B2D31), Theme.rgb(0x232528)],
                           startPoint: .top, endPoint: .bottom)
            LaunchHazard(vertical: book)
                .frame(width: book ? 12 : nil, height: book ? nil : 12)
            if lid {
                VStack(spacing: Theme.s2) {
                    Text("SQUISH")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Theme.yellow)
                        .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 4)
                    Text("THE MUSEUM OF PRESSED THINGS")
                        .font(Theme.micro)
                        .tracking(Theme.microTracking * 1.6)
                        .foregroundStyle(Theme.paper.opacity(0.7))
                }
                .scaleEffect(stamped || reduceMotion ? 1 : 1.35)
                .opacity(stamped ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.22, dampingFraction: 0.55),
                           value: stamped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            GeometryReader { proxy in
                ForEach(0..<4, id: \.self) { index in
                    LaunchBolt()
                        .position(x: index % 2 == 0 ? 26 : proxy.size.width - 26,
                                  y: index < 2 ? 26 : proxy.size.height - 26)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct LaunchHazard: View {
    let vertical: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.yellow))
            let period: CGFloat = 18
            let reach = max(size.width, size.height)
            var t: CGFloat = -reach
            while t < reach * 2 {
                var path = Path()
                if vertical {
                    path.move(to: CGPoint(x: 0, y: t))
                    path.addLine(to: CGPoint(x: size.width, y: t + size.width))
                    path.addLine(to: CGPoint(x: size.width, y: t + size.width + period / 2))
                    path.addLine(to: CGPoint(x: 0, y: t + period / 2))
                } else {
                    path.move(to: CGPoint(x: t, y: 0))
                    path.addLine(to: CGPoint(x: t + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: t + size.height + period / 2, y: size.height))
                    path.addLine(to: CGPoint(x: t + period / 2, y: 0))
                }
                path.closeSubpath()
                context.fill(path, with: .color(Theme.graphite))
                t += period
            }
        }
    }
}

private struct LaunchBolt: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.rgb(0xE6E8EC), Theme.rgb(0x8A8F98)], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .overlay(Rectangle().fill(Theme.rgb(0x5A5E66)).frame(width: 6, height: 1.5).rotationEffect(.degrees(35)))
            .frame(width: 10, height: 10)
            .shadow(color: .black.opacity(0.4), radius: 0.5, y: 1)
    }
}
