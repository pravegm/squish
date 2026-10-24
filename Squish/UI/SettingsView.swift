import SwiftUI
import UIKit

/// Settings (S9, UX-AUDIT-2 §4.2): one calm sheet, one tap from the press room, the reveal and the cover. Every
/// change saves immediately. Sound and vibration can be tested right here; "Sound & vibration check" mirrors the Tuning
/// Lab's diagnostics. Long-press the version row to open the Tuning Lab (on-device tuning and the hinge log).
struct SettingsView: View {
    let director: PressDirector
    /// Replays the first-run lesson (S1) on the press; nil hides the row.
    var onReplayIntro: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTuning = false
    @State private var showSoundCheck = false
    @State private var showHelp = false
    @State private var appeared = false
    /// A hinge has reported at some point (RootView sets it), so a Duo never gets non-Duo copy.
    @AppStorage("squish.hasHinge") private var hasHinge = false

    private var gameCenter: GameCenter { GameCenter.shared }

    /// Everything persisted, so one `onChange` saves any edit.
    private struct Snapshot: Equatable {
        var sound: Bool
        var playOnSilent: Bool
        var style: SoundStyle
        var haptics: HapticsLevel
        var strength: VibrationStrength
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
            // The same 560 pt column as the sections, so on a wide sheet (Duo, 669 pt) the title lines up with them.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s5) {
                    soundSection(settings)
                    feelSection(settings)
                    helpSection

                    if showsGameCenter {
                        section("Game Center", index: 3) {
                            gameCenterRow
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.s2) {
                        sectionTitle("About")
                        NavCard(title: "Sound & vibration check", systemImage: "waveform",
                                footnote: "Test buttons, and what your phone says about sound and vibration.") {
                            showSoundCheck = true
                        }
                        AboutRows(director: director, showTuning: $showTuning)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 8)
                    .animation(Theme.row(4, reduceMotion), value: appeared)
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
        .sheet(isPresented: $showSoundCheck) {
            SoundCheckView(director: director)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
                .creaseSafe()
        }
        .sheet(isPresented: $showHelp) {
            HelpView(onReplayIntro: replayIntroFromHelp)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground { AlbumPage(dots: false) }
                .sheetTypeCap()
                .creaseSafe()
        }
        .onAppear { appeared = true }
        .onChange(of: Snapshot(sound: settings.soundEnabled, playOnSilent: settings.playSoundInSilentMode,
                               style: settings.soundStyle, haptics: settings.hapticsLevel, strength: settings.vibrationStrength,
                               captions: settings.showCaptions, noFold: settings.pressWithoutFolding)) { _, _ in
            settings.save()
            UIFeel.enabled = settings.hapticsLevel != .off
        }
    }

    // MARK: Sections

    private func soundSection(_ model: AppSettings) -> some View {
        @Bindable var settings = model
        return section("Sound", index: 0) {
            ToggleRow(title: "Sound", isOn: $settings.soundEnabled)
            divider
            // The audio engineer's switch (AppSettings.playSoundInSilentMode → AudioSessionChoice), on by default.
            ToggleRow(title: "Play when phone is on Silent", isOn: $settings.playSoundInSilentMode,
                      footnote: settings.playSoundInSilentMode
                        ? "Squish plays even with the Silent switch on: the sound is half the toy. Your music keeps playing."
                        : "Squish follows the Silent switch. Can't hear it? Flip Silent off, or turn this on.")
                .disabled(!settings.soundEnabled)
            divider
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Sound style").font(Theme.body).foregroundStyle(Theme.ink)
                ChipChoice(selection: $settings.soundStyle, options: SoundStyle.allCases) { $0.title }
                    .disabled(!settings.soundEnabled)
                Text((settings.soundStyle == .soft
                      ? "Soft is gentler: rounder highs, fewer crunches, nothing wet."
                      : "Workshop is the full mix: every crack, crunch and fizz.").keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.s3)
            divider
            TestRow(title: "Play a test sound", systemImage: "speaker.wave.2.fill") {
                director.audio.playTestSound()
            }
            .disabled(!settings.soundEnabled)
        }
    }

    private func feelSection(_ model: AppSettings) -> some View {
        @Bindable var settings = model
        return section("Feel", index: 1) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Haptics").font(Theme.body).foregroundStyle(Theme.ink)
                ChipChoice(selection: $settings.hapticsLevel, options: HapticsLevel.allCases) { $0.title }
            }
            .padding(.vertical, Theme.s3)
            divider
            // MARK: Vibration strength (feedback engineer's row: Normal / Strong / Max, default Strong)
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("Vibration strength").font(Theme.body).foregroundStyle(Theme.ink)
                ChipChoice(selection: $settings.vibrationStrength, options: VibrationStrength.allCases) { $0.title }
                    .disabled(settings.hapticsLevel == .off)
            }
            .padding(.vertical, Theme.s3)
            // MARK: end vibration strength
            divider
            TestRow(title: "Test vibration", systemImage: "iphone.radiowaves.left.and.right") {
                director.haptics.playTestVibration()
            }
            divider
            ToggleRow(title: "Captions", isOn: $settings.showCaptions,
                      footnote: "Big comic words like POP! and CRACK! Always on for your first \(CoachLine.presses) presses.")
            divider
            if director.hingeAvailable || hasHinge {
                ToggleRow(title: "Press without folding", isOn: $settings.pressWithoutFolding,
                          footnote: "Drag down on the screen instead of folding. Handy one-handed, or when folding isn't comfortable.")
            } else {
                // Short enough for one line on a 6.1" phone (P6 broke it as "… folding / and dragging.").
                InfoRow(title: "Press by dragging", value: "ALWAYS ON",
                        footnote: "On iPhone Duo you can also press by folding.")
            }
            divider
            // The path never breaks inside itself (FOLD-REVIEW-7 N7).
            InfoRow(title: "Reduce Motion", value: reduceMotion ? "ON" : "OFF",
                    footnote: "Follows your iPhone setting (\(Self.settingsPath("Accessibility", "Motion"))). On: calmer animations, no shakes.")
        }
    }

    private var helpSection: some View {
        section("Help", index: 2) {
            NavRow(title: "How to press", systemImage: "questionmark.circle.fill") { showHelp = true }
            if onReplayIntro != nil {
                divider
                NavRow(title: "Replay intro", systemImage: "play.circle.fill") {
                    let replay = onReplayIntro
                    dismiss()
                    replay?()
                }
            }
        }
    }

    /// From the How to press sheet: close Settings too, then replay on the press.
    private var replayIntroFromHelp: (() -> Void)? {
        guard let onReplayIntro else { return nil }
        let close = dismiss
        return {
            close()
            onReplayIntro()
        }
    }

    // MARK: Rows

    /// `-squishDemo …;gamecenter=hidden` drops the whole section (store frames 07 / P6).
    private var showsGameCenter: Bool { !GameCenterRowDemo.hidesRow }

    /// Never a status word a buyer reads as broken (FOLD-REVIEW-6 N5: "Game Center · NOT AVAILABLE" in 07 and P6).
    /// Signed out, not yet asked, or Game Center unreachable all read the same, neutral way: achievements are kept
    /// here, and signing in happens in the iPhone's Settings (we only hold a sign-in sheet when the system gave us one).
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
        } else if gameCenter.isUnavailable {
            // Asked, and Game Center said no (signed out, restricted, or offline).
            InfoRow(title: "Sign in to Game Center in Settings",
                    footnote: "On your iPhone: \(Self.settingsPath("Game Center")). Until then, achievements you earn are kept here.")
        } else {
            // Not asked yet (the first run defers it, P1-7): no claim either way.
            InfoRow(title: "Game Center",
                    footnote: "Achievements you earn are kept on this iPhone and sent to Game Center once you're signed in.")
        }
    }

    /// "Settings › Accessibility › Motion" with no-break spaces, so the path wraps as one piece.
    private static func settingsPath(_ parts: String...) -> String {
        (["Settings"] + parts).joined(separator: " › ").replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private var divider: some View {
        Rectangle().fill(Theme.paperEdge.opacity(0.8)).frame(height: 1)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.label)
            .tracking(Theme.labelTracking)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.leading, Theme.s1)
            .accessibilityAddTraits(.isHeader)
    }

    /// A section card (§6.7): paperWarm, E1, radius 18, 16 pt padding; rows stagger in 40 ms apart.
    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.s2) {
            sectionTitle(title)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, Theme.s4)
            .padding(.vertical, Theme.s1)
            .background { shape.fill(Theme.paperWarm).elevation(.e1) }
            .topHighlight(cornerRadius: Theme.sectionRadius)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .animation(Theme.row(index, reduceMotion), value: appeared)
    }
}

// MARK: - Row components

/// A row that plays a test right here ("Play a test sound").
private struct TestRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s3) {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.graphite)
                    .frame(width: 24)
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s2)
                Text("PLAY")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.graphite)
                    .padding(.horizontal, Theme.s2)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.yellow))
            }
            .frame(minHeight: Theme.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .padding(.vertical, Theme.s2)
        .accessibilityLabel(title)
    }
}

/// A row that opens something ("How to press", "Replay intro").
private struct NavRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s3) {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.graphite)
                    .frame(width: 24)
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s2)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(minHeight: Theme.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .padding(.vertical, Theme.s2)
        .accessibilityLabel(title)
    }
}

/// A card-sized NavRow with a footnote (the Sound & vibration check).
private struct NavCard: View {
    let title: String
    let systemImage: String
    let footnote: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            NavRow(title: title, systemImage: systemImage, action: action)
            Text(footnote.keepingLastWordsTogether)
                .font(Theme.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.s3)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s1)
        .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        .topHighlight(cornerRadius: Theme.sectionRadius)
    }
}

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
                Text(footnote.keepingLastWordsTogether)
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
    /// The status word on the trailing edge; nil for a row that is only a title and a footnote.
    var value: String? = nil
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s2)
                if let value {
                    Text(value)
                        .font(Theme.label)
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(minHeight: Theme.hit)
            if let footnote {
                Text(footnote.keepingLastWordsTogether)
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

// MARK: - Line breaks

extension String {
    /// Joins the last two words with a no-break space, so a wrapped line never ends on one word alone
    /// (FOLD-REVIEW-6 N11: "… for each / moment.", "the / press."). Unchanged when there is nothing to join.
    ///
    /// Also unchanged when the last word is already long (more than `orphanGlueLimit` characters) or is itself an
    /// unbreakable run (it holds a no-break space, like a `settingsPath`): a long last word isn't an orphan, and
    /// gluing the word before it on makes a unit too wide for the line. FOLD-REVIEW-7 N7: "Follows your iPhone /
    /// setting (Settings › Accessibility › Motion)." now breaks as "Follows your iPhone setting / (Settings › …)."
    var keepingLastWordsTogether: String {
        guard let space = lastIndex(of: " "), space != startIndex, index(after: space) != endIndex else { return self }
        let lastWord = self[index(after: space)...]
        guard lastWord.count <= Self.orphanGlueLimit, !lastWord.contains("\u{00A0}") else { return self }
        return replacingCharacters(in: space...space, with: "\u{00A0}")
    }

    /// The longest last word `keepingLastWordsTogether` still glues to the one before it.
    static let orphanGlueLimit = 12

    /// " · " with no-break spaces on both sides, so the separator always travels with its neighbours and no wrapped
    /// line ends (or starts) on it (FOLD-REVIEW-7 N6: "PERFECT · / №0001", "THINGS · / 1/3").
    var gluingDotSeparators: String {
        replacingOccurrences(of: " · ", with: "\u{00A0}·\u{00A0}")
    }
}

// MARK: - Demo

/// `-squishDemo …;gamecenter=hidden` (FOLD-REVIEW-6 N5): Settings leaves out the Game Center section, for the store
/// frames. Read here, from the same launch argument `DemoScenario` parses (`key=value;key`), like `RevealToastDemo`,
/// so DemoMode.swift doesn't change. DEBUG only: always false in Release.
enum GameCenterRowDemo {
    static let hidesRow: Bool = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "squishDemo") else { return false }
        return raw.split(separator: ";").contains { part in
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return pieces.first == "gamecenter" && pieces.count > 1 && pieces[1] == "hidden"
        }
        #else
        return false
        #endif
    }()
}
