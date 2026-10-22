import Observation
import SwiftUI
import UIKit

/// Something ready for the system share sheet (bible §10: system share sheet only).
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Drives "Share image" and "Share clip" for one screen: renders, shows progress, surfaces friendly errors.
@MainActor
@Observable
final class SpecimenShareModel {
    var item: ShareItem?
    /// Non-nil while a clip is rendering (0…1).
    private(set) var clipProgress: Double?
    var showingError = false
    private(set) var errorMessage = ""

    @ObservationIgnored private var exporter: ClipExporter?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    var isExporting: Bool { clipProgress != nil }

    func shareImage(specimen: SpecimenRecord, thumbnail: UIImage?) {
        UIFeel.tick()
        guard let url = ShareImageRenderer.renderFile(specimen: specimen, thumbnail: thumbnail) else {
            fail("The image smudged. Try again?")
            return
        }
        item = ShareItem(url: url)
    }

    func shareClip(trace: PressTrace, specimen: SpecimenRecord) {
        guard exportTask == nil else { return }
        UIFeel.tick()
        clipProgress = 0
        let exporter = ClipExporter()
        self.exporter = exporter
        exportTask = Task { @MainActor [weak self] in
            do {
                let url = try await exporter.export(trace: trace, specimen: specimen) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.clipProgress != nil else { return }
                        self.clipProgress = min(max(progress, 0), 1)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.finishExport()
                self.item = ShareItem(url: url)
                UIFeel.success()
            } catch {
                guard let self else { return }
                let cancelled = Task.isCancelled || error is CancellationError
                self.finishExport()
                if !cancelled {
                    self.fail("The clip didn't render this time. Your specimen is safe — try again, or share the image instead.")
                }
            }
        }
    }

    func cancelClip() {
        exportTask?.cancel()
        finishExport()
    }

    private func finishExport() {
        clipProgress = nil
        exportTask = nil
        exporter = nil
    }

    private func fail(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

/// Presents the share sheet, clip progress and errors for a `SpecimenShareModel`.
struct SpecimenSharingChrome: ViewModifier {
    @Bindable var model: SpecimenShareModel

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress = model.clipProgress {
                    ClipProgressCard(progress: progress, onCancel: model.cancelClip)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(Theme.fade, value: model.isExporting)
            .onDisappear {
                // A sheet closing under an export cancels it rather than leaving a dangling task (P2-10).
                if model.isExporting { model.cancelClip() }
            }
            .sheet(item: $model.item) { item in
                ActivityView(items: [item.url])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert("Something went sideways", isPresented: $model.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage)
            }
    }
}

private struct ClipProgressCard: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.shadowInk.opacity(0.25).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.s4) {
                HStack(spacing: Theme.s3) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.graphite)
                        .frame(width: 40, height: 40)
                        .background(Theme.yellow, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developing your clip")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Re-pressing it frame by frame…")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.paperShade)
                        Capsule()
                            .fill(Theme.yellow)
                            .frame(width: max(14, proxy.size.width * progress))
                            .animation(.easeOut(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 14)
                HStack {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(Theme.label)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(KeycapStyle(kind: .secondary))
                }
            }
            .padding(Theme.s5)
            .background(PaperBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)))
            .topHighlight(cornerRadius: Theme.cardRadius)
            .elevation(.e3)
            .frame(maxWidth: 380)
            .padding(Theme.s5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Developing your clip, \(Int((progress * 100).rounded())) percent")
        }
    }
}

/// UIKit share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
