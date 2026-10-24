import SwiftUI
import UIKit

/// Settings → About → "Sound & vibration check" (EXPERIENCE-PLAN decision 8): the Tuning Lab's Diagnostics, mirrored
/// for everyone. The same rows (`AudioController` / `HapticsController.diagnosticRows()`) and the same test buttons, in
/// plain words, so "I can't hear it" has an answer without the hidden lab.
struct SoundCheckView: View {
    let director: PressDirector
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text("Sound & vibration check")
                        .font(Theme.sheetTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("ORANGE ROWS COULD EXPLAIN SILENCE")
                        .font(Theme.label)
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(KeycapStyle(kind: .secondary, round: true))
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, 20)
            .padding(.bottom, Theme.s3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    VStack(spacing: Theme.s2) {
                        testKey("Play a test sound", "speaker.wave.2.fill", primary: true) {
                            director.audio.playTestSound()
                            message = "Test sound sent. Heard nothing? Check the Sound rows below."
                        }
                        testKey("Test vibration", "iphone.radiowaves.left.and.right") {
                            director.haptics.playTestVibration()
                            message = "Test vibration sent, at full strength."
                        }
                        testKey("Test a full press", "rectangle.compress.vertical") {
                            director.playPressFeelTest()
                            message = "Strain, three cracks, the break, then the ka-chunk."
                        }
                        if let message {
                            Text(message)
                                .font(Theme.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        VStack(alignment: .leading, spacing: Theme.s4) {
                            group("Sound", director.audio.diagnosticRows())
                            group("Vibration", director.haptics.diagnosticRows())
                        }
                    }
                    Button {
                        UIPasteboard.general.string = report()
                        message = "Copied. Paste it into a message to us."
                    } label: {
                        KeyLabel(title: "Copy this report", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))
                    Text("The vibration tests play at full strength whatever your Haptics setting.".keepingLastWordsTogether)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s6)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func testKey(_ title: String, _ symbol: String, primary: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KeyLabel(title: title, systemImage: symbol)
        }
        .buttonStyle(KeycapStyle(kind: primary ? .primary : .secondary, fullWidth: true))
    }

    private func group(_ title: String, _ rows: [DiagnosticRow]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.s2) {
            Text(title.uppercased())
                .font(Theme.label)
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer(minLength: Theme.s2)
                        Text(row.value)
                            .font(Theme.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(row.isWarning ? Color.orange : Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Theme.s4)
            .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        }
    }

    private func report() -> String {
        var lines = ["Squish sound & vibration check, \(Date().formatted(date: .abbreviated, time: .standard))"]
        for (title, rows) in [("SOUND", director.audio.diagnosticRows()), ("VIBRATION", director.haptics.diagnosticRows())] {
            lines.append("")
            lines.append(title)
            for row in rows {
                lines.append("\(row.isWarning ? "! " : "  ")\(row.title): \(row.value)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
