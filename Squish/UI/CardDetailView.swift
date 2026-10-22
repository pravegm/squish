import SwiftUI
import UIKit

/// Card detail (bible §5 screen 3, VISUAL-TARGET §6.7–6.8): the pressed specimen at full size, its traits,
/// and Share Clip / Share Image / Delete keycaps.
struct CardDetailView: View {
    let director: PressDirector
    let specimenID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var share = SpecimenShareModel()
    @State private var confirmingDelete = false

    private var collection: CollectionStore { director.collection }
    private var specimen: SpecimenRecord? { collection.specimen(withID: specimenID) }

    /// Clips re-render from the stored hinge trace of that press.
    private func trace(for specimen: SpecimenRecord) -> PressTrace? {
        director.trace(for: specimen)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text("Specimen")
                        .font(Theme.sheetTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let specimen {
                        Text("\(specimen.numberLabel) · \(specimen.date.formatted(.dateTime.day().month(.abbreviated).year()).uppercased())")
                            .font(Theme.label)
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(KeycapStyle(kind: .secondary, round: true))
                .accessibilityLabel("Close card")
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, 20)
            .padding(.bottom, Theme.s3)

            if let specimen {
                ScrollView {
                    VStack(spacing: Theme.s5) {
                        SpecimenCardView(specimen: specimen, thumbnail: collection.thumbnail(for: specimen), style: .detail)
                            .frame(maxWidth: 400)
                            .padding(.top, Theme.s2)
                        if !specimen.traits.isEmpty {
                            FlowLayout(spacing: Theme.s2, lineSpacing: Theme.s2) {
                                ForEach(specimen.traits) { trait in
                                    TraitChip(text: trait.text, systemImage: trait.systemImage, tone: trait.tone)
                                }
                            }
                            .frame(maxWidth: 400, alignment: .leading)
                            .accessibilityHidden(true) // part of the card's sentence
                        }
                        actions(for: specimen)
                            .frame(maxWidth: 400)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s6)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("This card was removed.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modifier(SpecimenSharingChrome(model: share))
        .confirmationDialog("Delete this card?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                collection.delete(specimenID)
                UIFeel.tick()
                dismiss()
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("Only the card goes. Your presses, unlocks and achievements stay.")
        }
    }

    @ViewBuilder
    private func actions(for specimen: SpecimenRecord) -> some View {
        let clipTrace = trace(for: specimen)
        VStack(spacing: Theme.s3) {
            Button {
                if let clipTrace { share.shareClip(trace: clipTrace, specimen: specimen) }
            } label: {
                KeyLabel(title: "Share Clip", systemImage: "film")
            }
            .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true))
            .disabled(clipTrace == nil || share.isExporting)
            .accessibilityHint(clipTrace == nil ? "No recording was kept for this press." : "Renders a short video of this press.")

            Button {
                share.shareImage(specimen: specimen, thumbnail: collection.thumbnail(for: specimen))
            } label: {
                KeyLabel(title: "Share Image", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                KeyLabel(title: "Delete Card", systemImage: "trash")
            }
            .buttonStyle(KeycapStyle(kind: .destructive, fullWidth: true))
            .padding(.top, Theme.s2)
        }
    }
}
