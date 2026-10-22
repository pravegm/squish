import Foundation

/// Renders a 9:16 share clip of a press (bible §10). Placeholder until the export engineer lands the renderer.
@MainActor
final class ClipExporter {
    enum ExportError: LocalizedError {
        case notReady

        var errorDescription: String? {
            "Clip sharing is coming soon. Share the image for now."
        }
    }

    init() {}

    func export(trace: PressTrace, specimen: SpecimenRecord, progress: @escaping (Double) -> Void) async throws -> URL {
        throw ExportError.notReady
    }
}
