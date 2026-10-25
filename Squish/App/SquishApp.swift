import SwiftUI

@main
struct SquishApp: App {
    /// Phones without a hinge stay in portrait (UI/OrientationLock.swift).
    @UIApplicationDelegateAdaptor(SquishAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
