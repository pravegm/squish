import SwiftUI

/// The "pressed specimen" card shown on reopen (bible §5): label in SF Mono, red PRESSED stamp, flavour line.
struct RevealCardView: View {
    let result: PressResult
    let specimenNumber: Int
    let onNext: () -> Void

    private var tons: Int {
        12 + Int(result.maxCompression * 50) + Int(result.seed % 9)
    }

    private var flavour: String {
        let lines = result.kind.flavourLines
        return lines[Int(result.seed % UInt64(lines.count))]
    }

    private var stampAngle: Double {
        -12 + Double(result.seed % 9)
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(result.kind.displayName.uppercased())
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.graphiteColor)
                    Spacer()
                    Text(String(format: "№%04d", specimenNumber))
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Palette.graphiteColor.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let angle = result.failureAngle {
                        specimenLine("CRUSHED AT \(Int(angle.rounded()))°")
                    }
                    specimenLine("PEAK \(tons) TONS")
                    specimenLine(breaksLine)
                    specimenLine(String(format: "PRESS TIME %.1f S", result.duration))
                }

                HStack(spacing: 8) {
                    if result.isPerfect { trait("PERFECT SQUISH", systemImage: "sparkles") }
                    if result.wasSlammed { trait("SLAM", systemImage: "bolt.fill") }
                }

                Text(flavour)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Palette.graphiteColor.opacity(0.75))

                Button(action: onNext) {
                    Text("Next")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Palette.graphiteColor)
                        .background(Palette.yellowColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Color(white: 0.985), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Text("PRESSED")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.stampColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.stampColor, lineWidth: 3))
                    .rotationEffect(.degrees(stampAngle))
                    .opacity(0.85)
                    .offset(x: -18, y: 54)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(16)
            .frame(maxWidth: 460)
        }
        .accessibilityElement(children: .contain)
    }

    private var breaksLine: String {
        switch result.kind {
        case .bubbleWrap: "\(result.fractureCount) POPS"
        case .rubberDuck: result.fractureCount >= 2 ? "1 HONK · 1 SEAM POP" : "\(result.fractureCount) HONK"
        }
    }

    private func specimenLine(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .monospaced, weight: .medium))
            .foregroundStyle(Palette.graphiteColor)
    }

    private func trait(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Palette.graphiteColor)
            .background(Palette.yellowColor.opacity(0.35), in: Capsule())
    }
}

/// What the outer display shows while the phone is shut: the sealed press, or an invitation to open.
struct CoverView: View {
    let director: PressDirector

    var body: some View {
        ZStack {
            Palette.graphiteColor.ignoresSafeArea()
            VStack(spacing: 16) {
                if director.engine.phase == .sealed, let result = director.engine.lastResult {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Palette.yellowColor)
                    Text("PRESS SEALED")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("\(12 + Int(result.maxCompression * 50) + Int(result.seed % 9)) TONS")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("Open to see")
                        .font(.system(.headline, design: .rounded))
                        .opacity(0.7)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Palette.yellowColor)
                    Text("Open to press")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text(director.currentKind.displayName)
                        .font(.system(.headline, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}
