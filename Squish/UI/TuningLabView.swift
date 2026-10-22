import SwiftUI
import UIKit

/// On-device tuning for every constant in bible §6–8, plus the raw hinge log that replaces a separate Hinge Lab.
struct TuningLabView: View {
    let director: PressDirector
    @Environment(\.dismiss) private var dismiss
    @State private var copiedMessage: String?

    var body: some View {
        @Bindable var engine = director.engine
        NavigationStack {
            Form {
                Section("Feel") {
                    Picker("Haptics", selection: $engine.config.hapticsScale) {
                        Text("Off").tag(0.0)
                        Text("Soft").tag(0.6)
                        Text("Full").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Sound", isOn: $engine.config.soundEnabled)
                    TuneSlider(title: "Volume", value: $engine.config.soundVolume, range: 0...1, format: "%.2f")
                }

                Section("Live") {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        VStack(alignment: .leading, spacing: 4) {
                            liveRow("Phase", engine.phase.rawValue)
                            liveRow("Hinge", director.hingeAvailable ? "available" : "touch fallback")
                            liveRow("Raw angle", String(format: "%.1f°", engine.rawAngle))
                            liveRow("Filtered", String(format: "%.1f°", engine.angle))
                            liveRow("Closing speed", String(format: "%.0f°/s", engine.closingSpeed))
                            liveRow("Depth (measured)", String(format: "%.3f", engine.measuredDepth))
                            liveRow("Depth (render)", String(format: "%.3f", engine.renderDepth))
                            liveRow("Plastic", String(format: "%.3f", engine.plasticDepth))
                            liveRow("Max compression", String(format: "%.3f", engine.maxCompression))
                            liveRow("Hinge updates", String(format: "%.0f / s", director.hingeLog.recentRate))
                            liveRow("Samples logged", "\(director.hingeLog.samples.count)")
                        }
                        .font(.system(.footnote, design: .monospaced))
                    }
                }

                Section {
                    TuneSlider(title: "Arm angle max", value: $engine.config.armAngleMax, range: 130...179, format: "%.0f°")
                    TuneSlider(title: "End angle (θ_end)", value: $engine.config.endAngle, range: 20...100, format: "%.0f°")
                    TuneSlider(title: "Contact point", value: $engine.config.contactT, range: 0.05...0.4, format: "%.2f")
                    TuneSlider(title: "Ease exponent", value: $engine.config.easeExponent, range: 0.8...3, format: "%.2f")
                    TuneSlider(title: "Hysteresis", value: $engine.config.hysteresis, range: 1...10, format: "%.1f°")
                    TuneSlider(title: "Reveal angle", value: $engine.config.revealAngle, range: 60...170, format: "%.0f°")
                } header: {
                    Text("Mapping")
                } footer: {
                    Text("Tip: close slowly and note the raw angle when the inner screen turns off. Set the end angle a few degrees above it.")
                }

                Section("Smoothing") {
                    TuneSlider(title: "1€ min cutoff", value: $engine.config.oneEuroMinCutoff, range: 0.1...5, format: "%.2f Hz")
                    TuneSlider(title: "1€ beta", value: $engine.config.oneEuroBeta, range: 0...0.3, format: "%.3f")
                    TuneSlider(title: "Spring ω", value: $engine.config.springOmega, range: 5...60, format: "%.0f")
                    TuneSlider(title: "Max prediction", value: $engine.config.maxPredict, range: 0...0.12, format: "%.3f s")
                }

                Section("Export") {
                    Button("Copy config JSON") {
                        UIPasteboard.general.string = engine.config.prettyJSON()
                        copiedMessage = "Config copied"
                    }
                    Button("Copy hinge log CSV") {
                        UIPasteboard.general.string = director.hingeLog.csv()
                        copiedMessage = "Hinge log copied (\(director.hingeLog.samples.count) samples)"
                    }
                    Button("Clear hinge log", role: .destructive) {
                        director.hingeLog.clear()
                    }
                    Button("Reset to defaults", role: .destructive) {
                        engine.config = .standard
                    }
                    if let copiedMessage {
                        Text(copiedMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tuning Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            director.engine.config.save()
        }
    }

    private func liveRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private struct TuneSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
