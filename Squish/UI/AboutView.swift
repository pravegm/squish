import SwiftUI

/// Menu → About (S8): credits, Golden odds, privacy, support and the version. The Tuning Lab stays a long-press on the
/// version, so nobody finds it by accident.
struct AboutView: View {
    let director: PressDirector
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showTuning = false

    private static let supportURL = URL(string: "https://pravegm.github.io/squish/support/")!
    private static let privacyURL = URL(string: "https://pravegm.github.io/squish/privacy/")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
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
            .padding(.top, 16)
            ScrollView {
                VStack(spacing: Theme.s5) {
                    VStack(spacing: Theme.s2) {
                        AppIconArt()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .elevation(.e2)
                            .accessibilityHidden(true)
                        Text("Squish")
                            .font(Theme.display)
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("THE MUSEUM OF PRESSED THINGS")
                            .font(Theme.label)
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    AboutRows(director: director, showTuning: $showTuning)
                    HStack(spacing: Theme.s2) {
                        Button {
                            openURL(Self.supportURL)
                        } label: {
                            KeyLabel(title: "Support", systemImage: "envelope.fill")
                        }
                        .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))
                        .accessibilityHint("Opens the support page in Safari.")
                        Button {
                            openURL(Self.privacyURL)
                        } label: {
                            KeyLabel(title: "Privacy", systemImage: "hand.raised.fill")
                        }
                        .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))
                        .accessibilityHint("Opens the privacy policy in Safari.")
                    }
                }
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s6)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showTuning) {
            TuningLabView(director: director)
        }
    }
}

/// The About facts, shared by the About screen and Settings → About.
struct AboutRows: View {
    let director: PressDirector
    @Binding var showTuning: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.sectionRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            versionRow
            divider
            row("Golden variants", value: "1 IN \(PressVariant.goldenOdds)",
                footnote: "Every press has the same odds. Nothing is for sale.")
            divider
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("No ads. No tracking. No in-app purchases.")
                    .font(Theme.button)
                    .foregroundStyle(Theme.ink)
                Text("Made by a tiny studio. Recorded foley and sounds synthesised as you press, tuned for this phone. Thanks to everyone who closed their phone very, very slowly.".keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.s3)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s1)
        .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        .topHighlight(cornerRadius: Theme.sectionRadius)
    }

    private var versionRow: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return row("Version", value: "\(version) (\(build))")
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.8) {
                UIFeel.press()
                showTuning = true
            }
            .accessibilityAction(named: "Open Tuning Lab") { showTuning = true }
    }

    private var divider: some View {
        Rectangle().fill(Theme.paperEdge.opacity(0.8)).frame(height: 1)
    }

    private func row(_ title: String, value: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack {
                Text(title).font(Theme.body).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s2)
                Text(value)
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
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
