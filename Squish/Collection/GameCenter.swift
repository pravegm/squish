import GameKit
import Observation
import UIKit
import os

/// Thin, polite Game Center wrapper (bible §11). Authentication is silent: if the system hands us a sign-in
/// view controller we keep it and never present it on our own. Settings offers a "Sign in" row instead.
/// Achievements earned while signed out are queued and reported once a player is authenticated.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    /// Signed-in state, for the Settings row.
    private(set) var isAuthenticated = false
    private(set) var playerName: String?
    /// The system's sign-in UI, held until the player asks for it in Settings.
    private(set) var pendingSignIn: UIViewController?
    private(set) var isUnavailable = false

    @ObservationIgnored private var didStart = false
    private let pendingKey = "squish.gameCenter.pending"
    private let log = Logger(subsystem: "com.pravegm.squish", category: "gamecenter")

    private init() {}

    func authenticate() {
        guard !didStart else { return }
        didStart = true
        #if DEBUG
        // CI screenshot runs must never show Game Center banners.
        if DemoScenario.current != nil { isUnavailable = true; return }
        #endif
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            Task { @MainActor in
                GameCenter.shared.handleAuthentication(viewController: viewController, error: error)
            }
        }
    }

    func report(_ achievements: [Achievement]) {
        guard !achievements.isEmpty else { return }
        var queue = pendingIDs
        for achievement in achievements where !queue.contains(achievement.rawValue) {
            queue.append(achievement.rawValue)
        }
        pendingIDs = queue
        flush()
    }

    /// Presents the system sign-in sheet the player previously declined or skipped. Settings only.
    func presentSignIn() {
        guard let controller = pendingSignIn, let presenter = Self.topViewController() else { return }
        presenter.present(controller, animated: true)
    }

    // MARK: - Internals

    private var pendingIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    private func handleAuthentication(viewController: UIViewController?, error: Error?) {
        if let viewController {
            pendingSignIn = viewController
            isAuthenticated = false
            return
        }
        pendingSignIn = nil
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        playerName = isAuthenticated ? GKLocalPlayer.local.displayName : nil
        if let error {
            isUnavailable = !isAuthenticated
            log.info("Game Center unavailable: \(error.localizedDescription, privacy: .public)")
        }
        flush()
    }

    private func flush() {
        guard isAuthenticated else { return }
        let ids = pendingIDs
        guard !ids.isEmpty else { return }
        let achievements: [GKAchievement] = ids.compactMap { raw in
            guard let achievement = Achievement(rawValue: raw) else { return nil }
            let gk = GKAchievement(identifier: achievement.gameCenterID)
            gk.percentComplete = 100
            gk.showsCompletionBanner = true
            return gk
        }
        GKAchievement.report(achievements) { error in
            Task { @MainActor in
                GameCenter.shared.didReport(ids, error: error)
            }
        }
    }

    private func didReport(_ ids: [String], error: Error?) {
        if let error {
            log.info("Achievement report failed, will retry: \(error.localizedDescription, privacy: .public)")
            return
        }
        pendingIDs = pendingIDs.filter { !ids.contains($0) }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
