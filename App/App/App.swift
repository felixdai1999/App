import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
enum HomeScreenQuickAction: String {
    case newTab = "com.felix.apps.quickaction.newtab"
    case bookmarks = "com.felix.apps.quickaction.bookmarks"
    case history = "com.felix.apps.quickaction.history"
    case settings = "com.felix.apps.quickaction.settings"
}

extension Notification.Name {
    static let homeScreenQuickActionTriggered = Notification.Name("homeScreenQuickActionTriggered")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pendingQuickAction: HomeScreenQuickAction?

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = HomeScreenQuickAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        NotificationCenter.default.post(name: .homeScreenQuickActionTriggered, object: action)
        completionHandler(true)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem,
              let action = HomeScreenQuickAction(rawValue: shortcutItem.type) else { return }
        AppDelegate.pendingQuickAction = action
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .homeScreenQuickActionTriggered, object: action)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = HomeScreenQuickAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        AppDelegate.pendingQuickAction = action
        NotificationCenter.default.post(name: .homeScreenQuickActionTriggered, object: action)
        completionHandler(true)
    }
}
#endif

@main
struct BrowserApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(iOS)
                .onAppear {
                    configureHomeScreenQuickActions()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        configureHomeScreenQuickActions()
                    }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
    }

    #if os(iOS)
    private func configureHomeScreenQuickActions() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: HomeScreenQuickAction.newTab.rawValue,
                localizedTitle: "New Tab",
                localizedSubtitle: "Open a fresh tab",
                icon: UIApplicationShortcutIcon(systemImageName: "plus.square.on.square"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: HomeScreenQuickAction.bookmarks.rawValue,
                localizedTitle: "Bookmarks",
                localizedSubtitle: "View saved links",
                icon: UIApplicationShortcutIcon(systemImageName: "bookmark"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: HomeScreenQuickAction.history.rawValue,
                localizedTitle: "History",
                localizedSubtitle: "Open browsing history",
                icon: UIApplicationShortcutIcon(systemImageName: "clock"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: HomeScreenQuickAction.settings.rawValue,
                localizedTitle: "Settings",
                localizedSubtitle: "Customize your browser",
                icon: UIApplicationShortcutIcon(systemImageName: "gear"),
                userInfo: nil
            )
        ]
    }
    #endif
}
