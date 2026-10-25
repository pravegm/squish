import SwiftUI

/// Reads the iPhone Duo hinge (iOS 27.1+) and reports degrees (180 = flat) plus whether it is closed.
/// On devices without a hinge the context's `hinge` is nil and the touch fallback takes over.
///
/// Launch QA P1: back from the background with the phone already open and still, iOS may send no hinge change at all,
/// leaving a stale "shut". On every activation the subscription is switched off and on again, which delivers the
/// current hinge state (UIHingeInteraction: "on re-enable, the handler gets the current state").
struct HingeReader: ViewModifier {
    let onUpdate: (Double, Bool) -> Void
    let onUnavailable: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = true
    @State private var refresh = 0

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .onHingeChange(isEnabled: enabled) { _, newContext in
                    if let hinge = newContext.hinge {
                        onUpdate(hinge.angle.degrees, hinge.status == .closed)
                    } else {
                        onUnavailable()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    refresh &+= 1
                    let ticket = refresh
                    enabled = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(30))
                        guard ticket == refresh else { return }
                        enabled = true
                    }
                }
        } else {
            content.onAppear(perform: onUnavailable)
        }
    }
}
