import SwiftUI

/// Reads the iPhone Duo hinge (iOS 27.1+) and reports degrees (180 = flat) plus whether it is closed.
/// On devices without a hinge the context's `hinge` is nil and the touch fallback takes over.
struct HingeReader: ViewModifier {
    let onUpdate: (Double, Bool) -> Void
    let onUnavailable: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                if let hinge = newContext.hinge {
                    onUpdate(hinge.angle.degrees, hinge.status == .closed)
                } else {
                    onUnavailable()
                }
            }
        } else {
            content.onAppear(perform: onUnavailable)
        }
    }
}
