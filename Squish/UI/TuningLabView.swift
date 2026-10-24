import SwiftUI
import UIKit

/// On-device tuning for every constant in bible §6–8, plus the raw hinge log that replaces a separate Hinge Lab.
struct TuningLabView: View {
    let director: PressDirector
    @Environment(\.dismiss) private var dismiss
    @State private var copiedMessage: String?
    @State private var diagnosticsMessage: String?

    var body: some View {
        @Bindable var engine = director.engine
        NavigationStack {
            Form {
                diagnosticsSection

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
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let p = engine.pipeline
                        VStack(alignment: .leading, spacing: 4) {
                            liveRow("Hinge updates", String(format: "%.0f / s", p.hingeRate))
                            liveRow("Sample age", String(format: "%.0f ms", p.sampleAge * 1000))
                            liveRow("Filter lag", String(format: "%+.1f°", p.filterLag))
                            liveRow("Drawn vs raw", String(format: "%+.1f°", p.drawnVsRaw))
                            liveRow("Render vs raw", String(format: "%+.1f°", p.renderVsRaw))
                            liveRow("Display refresh", String(format: "%.0f Hz", p.displayRate))
                            liveRow("Last resume", director.fold.lastResumeLatency.map { String(format: "%.0f ms", $0 * 1000) } ?? "–")
                        }
                        .font(.system(.footnote, design: .monospaced))
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Screenshot this while folding. Drawn vs raw near 0 means the screen keeps up with the hand.")
                }

                Section {
                    TuneSlider(title: "Contact angle (squash starts)", value: $engine.config.contactCeiling, range: 60...160, format: "%.0f°")
                    TuneSlider(title: "Fully crushed angle", value: $engine.config.endAngle, range: 15...100, format: "%.0f°")
                    TuneSlider(title: "Display-off angle", value: $engine.config.displayOffAngle, range: 20...100, format: "%.0f°")
                    TuneSlider(title: "Shut angle (seals)", value: $engine.config.shutAngle, range: 2...40, format: "%.0f°")
                    TuneSlider(title: "Reveal opens at", value: $engine.config.revealOpenAngle, range: 15...90, format: "%.0f°")
                } header: {
                    Text("Angles")
                } footer: {
                    Text("Drag these on the phone, then Copy config JSON below and send it. Set the fully crushed angle a few degrees above where the inner screen turns off.")
                }

                Section {
                    TuneSlider(title: "Arm angle max", value: $engine.config.armAngleMax, range: 130...179, format: "%.0f°")
                    TuneSlider(title: "Contact point", value: $engine.config.contactT, range: 0.05...0.4, format: "%.2f")
                    TuneSlider(title: "Ease exponent", value: $engine.config.easeExponent, range: 0.8...3, format: "%.2f")
                    TuneSlider(title: "Hysteresis", value: $engine.config.hysteresis, range: 1...10, format: "%.1f°")
                    TuneSlider(title: "Reveal angle", value: $engine.config.revealAngle, range: 60...170, format: "%.0f°")
                } header: {
                    Text("Mapping")
                } footer: {
                    Text("Tip: close slowly and note the raw angle when the inner screen turns off. Set the end angle a few degrees above it.")
                }

                Section {
                    TuneSlider(title: "Arm angle min", value: $engine.config.armAngleMin, range: 60...160, format: "%.0f°")
                    TuneSlider(title: "Seal depth", value: $engine.config.sealDepth, range: 0.85...1, format: "%.2f")
                    TuneSlider(title: "Seal hold", value: $engine.config.sealHold, range: 0...0.5, format: "%.2f s")
                    TuneSlider(title: "Failure hush", value: $engine.config.failureHushDelay, range: 0...0.12, format: "%.3f s")
                    TuneSlider(title: "Slam speed", value: $engine.config.slamSpeed, range: 100...600, format: "%.0f°/s")
                    TuneSlider(title: "Perfect max speed", value: $engine.config.perfectMaxSpeed, range: 30...250, format: "%.0f°/s")
                } header: {
                    Text("Press & traits")
                } footer: {
                    Text("Sound, haptics and captions are user settings now (Settings sheet), not tuning values.")
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

    // MARK: - Diagnostics

    /// Plain-words device diagnostics for sound and vibration (Release builds have no console): read it, screenshot
    /// it, or copy it. Rows in orange could explain missing sound or vibration.
    private var diagnosticsSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    diagnosticsGroup("Sound", director.audio.diagnosticRows())
                    diagnosticsGroup("Vibration", director.haptics.diagnosticRows())
                    diagnosticsGroup("App", appRows)
                }
                .font(.system(.footnote, design: .monospaced))
            }
            Button("Test sound") {
                director.audio.playTestSound()
                diagnosticsMessage = "Test sound sent. Check \"Last audio event\"."
            }
            Button("Test vibration") {
                director.haptics.playTestVibration()
                diagnosticsMessage = "Test vibration sent (full strength)."
            }
            Button("Test full press feel") {
                director.playPressFeelTest()
                diagnosticsMessage = "Press feel test: strain, three cracks, the failure, then the ka-chunk."
            }
            Button("Vibration strength test") {
                director.playStrengthComparison()
                diagnosticsMessage = "Normal (1 pip), then Strong (2 pips), then Max (3 pips)."
            }
            Button("Copy diagnostics") {
                UIPasteboard.general.string = diagnosticsReport()
                diagnosticsMessage = "Diagnostics copied"
            }
            if let diagnosticsMessage {
                Text(diagnosticsMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Orange rows could explain missing sound or vibration. Screenshot this, or tap Copy diagnostics and paste it. The vibration tests play at full strength whatever the Haptics setting.")
        }
    }

    private func diagnosticsGroup(_ title: String, _ rows: [DiagnosticRow]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(row.isWarning ? Color.orange : Color.primary)
                }
            }
        }
    }

    private var appRows: [DiagnosticRow] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "Active"
        case .inactive: state = "Inactive"
        case .background: state = "Background"
        @unknown default: state = "Unknown"
        }
        return [
            DiagnosticRow(title: "Squish", value: "\(version) (\(build))"),
            DiagnosticRow(title: "Device", value: "\(Self.modelIdentifier) · iOS \(UIDevice.current.systemVersion)"),
            DiagnosticRow(title: "Press mode", value: director.usesFoldPress ? "Fold Press (hinge)" : "Touch press (P-48)"),
            DiagnosticRow(title: "Hinge", value: director.hingeAvailable
                ? (director.hingeClosed ? "Available, closed" : "Available, open") : "Not reporting"),
            DiagnosticRow(title: "Press loop frames", value: "\(director.diagnosticsFrameCount) (climbs while running)"),
            DiagnosticRow(title: "App state", value: state),
        ]
    }

    /// The whole panel as text, for pasting into a message.
    private func diagnosticsReport() -> String {
        var lines = ["Squish diagnostics, \(Date().formatted(date: .abbreviated, time: .standard))"]
        for (title, rows) in [("SOUND", director.audio.diagnosticRows()), ("VIBRATION", director.haptics.diagnosticRows()),
                              ("APP", appRows)] {
            lines.append("")
            lines.append(title)
            for row in rows {
                lines.append("\(row.isWarning ? "! " : "  ")\(row.title): \(row.value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "iPhone18,1"-style hardware identifier (no personal data).
    private static var modelIdentifier: String {
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
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
