import SwiftUI
import UIKit

/// Phones without a hinge are portrait-only (launch QA): the P-48 press, its Pinch handle, the lesson and the reveal
/// columns are built for portrait, and a wide window put them under the Dynamic Island with the drag on the wrong
/// axis. The iPhone Duo keeps every orientation (book pose is a landscape inner display): a hinge has reported on
/// this device before (`squish.hasHinge`), one reports now, or the screen already looks foldable (both Duo displays
/// are ~0.7 wide to tall; other iPhones ~0.46).
@MainActor
enum OrientationLock {
    /// A hinge reported in this run (RootView.hingeArrived), before `squish.hasHinge` was ever saved.
    private(set) static var hingeSeen = false

    static func mask(screen: CGSize) -> UIInterfaceOrientationMask {
        allowsLandscape(hasHinge: UserDefaults.standard.bool(forKey: "squish.hasHinge") || hingeSeen, screen: screen)
            ? .allButUpsideDown : .portrait
    }

    /// Pure rule (tested): landscape only on a device with a hinge, or one whose screen looks like a Duo's.
    nonisolated static func allowsLandscape(hasHinge: Bool, screen: CGSize) -> Bool {
        if hasHinge { return true }
        guard screen.width > 0, screen.height > 0 else { return false }
        return min(screen.width, screen.height) / max(screen.width, screen.height) > 0.6
    }

    /// A hinge just reported: let the windows rotate again if they were held in portrait.
    static func hingeArrived() {
        guard !hingeSeen else { return }
        hingeSeen = true
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

/// Supplies the orientation lock (`OrientationLock`) to UIKit.
@MainActor
final class SquishAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask(screen: window?.windowScene?.screen.bounds.size ?? .zero)
    }
}
