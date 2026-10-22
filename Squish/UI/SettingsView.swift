import SwiftUI
import UIKit

/// Settings (bible §5 screen 4, VISUAL-TARGET §6.7). One calm sheet, opened from the Shelf; every change saves
/// immediately. Long-press the version row to open the Tuning Lab (on-device tuning and the hinge log).
struct SettingsView: View {
    let director: PressDirector

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTuning = false
    @State private var appeared = false
    /// A hinge has reported at some point (RootView sets it), so a Duo never gets non-Duo copy.
    @AppStorage("squish.hasHinge") private var hasHinge = false

    private var gameCenter: GameCenter { GameCenter.shared }

    /// Everything persisted, so one `onChange` saves any edit.
    private struct Snapshot: Equatable {
        var sound: Bool
        var style: SoundStyle
        var haptics: HapticsLevel
        var captions: Bool
        var noFold: Bool
    }

    var body: some View {
        @Bindable var settings = director.settings
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text("Settings")
                        .font(Theme.sheetTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("SAVED AS YOU GO")
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
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, 20)
            .padding(.bottom, Theme.s3)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s5) {
                    section("Sound", index: 0) {
                        ToggleRow(title: "Sound", isOn: $settings.soundEnabled)
                        divider
                        VStack(alignment: .leading, spacing: Theme.s2) {
                            Text("Sound style").font(Theme.body).foregroundStyle(Theme.ink)
                            ChipChoice(selection: $settings.soundStyle, options: SoundStyle.allCases) { $0.title }
                                .disabled(!settings.soundEnabled)
                            Text(settings.soundStyle == .soft
                                 ? "Soft is gentler: rounder highs, fewer crunches, nothing wet."
                                 : "Workshop is the full mix: every crack, crunch and fizz.")
                                .font(Theme.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Theme.s3)
                    }

                    section("Feel", index: 1) {
                        VStack(alignment: .leading, spacing: Theme.s2) {
                            Text("Haptics").font(Theme.body).foregroundStyle(Theme.ink)
                            ChipChoice(selection: $settings.hapticsLevel, options: HapticsLevel.allCases) { $0.title }
                        }
                        .padding(.vertical, Theme.s3)
                        divider
                        ToggleRow(title: "Captions", isOn: $settings.showCaptions,
                                  footnote: "Big comic words like POP! and CRACK! for each moment.")
                        divider
                        if director.hingeAvailable || hasHinge {
                            ToggleRow(title: "Press without folding", isOn: $settings.pressWithoutFolding,
                                      footnote: "Drag down on the screen instead of folding. Handy one-handed, or when folding isn't comfortable.")
                        } else {
                            InfoRow(title: "Press by dragging", value: "ALWAYS ON",
                                    footnote: "On iPhone Duo you can choose between folding and dragging.")
                        }
                        divider
                        InfoRow(title: "Reduce Motion", value: reduceMotion ? "ON" : "OFF",
                                footnote: "Follows your iPhone setting (Settings › Accessibility › Motion).")
                    }

                    section("Game Center", index: 2) {
                        gameCenterRow
                    }

                    section("About", index: 3) {
                        versionRow
                        divider
                        InfoRow(title: "Golden variants", value: "1 IN \(PressVariant.goldenOdds)",
                                footnote: "Every press has the same odds. Nothing is for sale.")
                        divider
                        VStack(alignment: .leading, spacing: Theme.s2) {
                            Text("No ads. No tracking. No in-app purchases.")
                                .font(Theme.button)
                                .foregroundStyle(Theme.ink)
                            Text("Made by a tiny studio. Sounds from Sonniss GDC bundles and Freesound (CC0), the rest synthesised in code. Thanks to everyone who closed their phone very, very slowly.")
                                .font(Theme.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Theme.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.s4)
                .padding(.top, Theme.s2)
                .padding(.bottom, Theme.s6)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showTuning) {
            TuningLabView(director: director)
        }
        .onAppear { appeared = true }
        .onChange(of: Snapshot(sound: settings.soundEnabled, style: settings.soundStyle, haptics: settings.hapticsLevel,
                               captions: settings.showCaptions, noFold: settings.pressWithoutFolding)) { _, _ in
            settings.save()
            UIFeel.enabled = settings.hapticsLevel != .off
        }
    }

    // MARK: Rows

    private var versionRow: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return InfoRow(title: "Version", value: "\(version) (\(build))")
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.8) {
                UIFeel.press()
                showTuning = true
            }
            .accessibilityAction(named: "Open Tuning Lab") { showTuning = true }
    }

    @ViewBuilder
    private var gameCenterRow: some View {
        if gameCenter.isAuthenticated {
            InfoRow(title: "Signed in", value: (gameCenter.playerName ?? "").uppercased(),
                    footnote: "Achievements are reported as you earn them.")
        } else if gameCenter.pendingSignIn != nil {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Achievements you've earned are kept and sent once you sign in.")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                Button {
                    gameCenter.presentSignIn()
                } label: {
                    KeyLabel(title: "Sign In to Game Center", systemImage: "person.crop.circle")
                }
                .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))
            }
            .padding(.vertical, Theme.s3)
        } else {
            InfoRow(title: "Game Center", value: "NOT AVAILABLE",
                    footnote: "Achievements are saved on this iPhone and sent when Game Center is available.")
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.paperEdge.opacity(0.8)).frame(height: 1)
    }

    /// A section card (§6.7): paperWarm, E1, radius 18, 16 pt padding; rows stagger in 40 ms apart.
    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.s2) {
            Text(title.uppercased())
                .font(Theme.label)
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.leading, Theme.s1)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, Theme.s4)
            .padding(.vertical, Theme.s1)
            .background(Theme.paperWarm, in: shape)
            .topHighlight(cornerRadius: Theme.sectionRadius)
            .elevation(.e1)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .animation(Theme.row(index, reduceMotion), value: appeared)
    }
}

// MARK: - Row components

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Toggle(isOn: $isOn) {
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
            }
            .tint(Theme.yellow)
            .frame(minHeight: Theme.hit)
            if let footnote {
                Text(footnote)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.s3)
        .onChange(of: isOn) { _, _ in UIFeel.tick() }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s2)
                Text(value)
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: Theme.hit)
            if let footnote {
                Text(footnote)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.s3)
        .accessibilityElement(children: .combine)
    }
}

/// Segmented choice as a row of chip keycaps (§6.6); the chosen one sits yellow.
struct ChipChoice<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: Theme.s2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option).uppercased())
                }
                .buttonStyle(KeycapStyle(kind: .chip, selected: selected))
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}
