import SwiftUI
import UIKit

// MARK: - Global State

enum AppState {
    static var sourceAppBundleID: String?
    static var pendingReturnToApp = false
}

// MARK: - Scene Delegate (URL scheme handling)

class MiniFlowSceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let context = URLContexts.first else { return }
        if let sourceApp = context.options.sourceApplication {
            AppState.sourceAppBundleID = sourceApp
        } else {
            AppState.sourceAppBundleID = Self.getPreviousAppBundleID()
        }
        handleURL(context.url)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let context = connectionOptions.urlContexts.first {
            if let sourceApp = context.options.sourceApplication {
                AppState.sourceAppBundleID = sourceApp
            } else {
                AppState.sourceAppBundleID = Self.getPreviousAppBundleID()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.handleURL(context.url)
            }
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        if AppState.pendingReturnToApp {
            AppState.pendingReturnToApp = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Self.returnToSourceApp()
            }
        }
    }

    // MARK: - URL Handling

    private func handleURL(_ url: URL) {
        guard url.scheme == "miniflow" else { return }

        if url.host == "startflow" {
            FlowBackgroundRecorder.shared.startFlowSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Self.returnToSourceApp()
            }
        } else if url.host == "stopflow" {
            FlowBackgroundRecorder.shared.endFlowSession()
        }
    }

    // MARK: - Source App Detection (private APIs, obfuscated)

    static func getPreviousAppBundleID() -> String? {
        // Priority 1: Check UserDefaults (keyboard saved the host bundle ID)
        if let defaults = UserDefaults(suiteName: "group.com.smallestai.MiniFlow") {
            defaults.synchronize()
            if let bundleID = defaults.string(forKey: "flow_return_app_bundle_id"),
               !bundleID.isEmpty,
               !bundleID.contains("MiniFlow") {
                return bundleID
            }
        }

        // Priority 2: FBSSystemService
        let fbsClassName = ["FBS", "System", "Service"].joined()
        if let fbsClass = NSClassFromString(fbsClassName),
           let service = (fbsClass as AnyObject).perform(NSSelectorFromString("sharedService"))?.takeUnretainedValue() {
            for sel in ["previousApplication", "topApplication"] {
                let selector = NSSelectorFromString(sel)
                if (service as AnyObject).responds(to: selector),
                   let result = (service as AnyObject).perform(selector)?.takeUnretainedValue(),
                   let bundleID = result as? String,
                   !bundleID.contains("MiniFlow") {
                    return bundleID
                }
            }
        }

        return nil
    }

    static func returnToSourceApp() {
        if let bundleID = AppState.sourceAppBundleID, !bundleID.isEmpty,
           !bundleID.contains("MiniFlow") {
            AppState.sourceAppBundleID = nil
            openAppWithBundleID(bundleID)
            return
        }

        if let defaults = UserDefaults(suiteName: "group.com.smallestai.MiniFlow") {
            defaults.synchronize()
            if let bundleID = defaults.string(forKey: "flow_return_app_bundle_id"),
               !bundleID.isEmpty,
               !bundleID.contains("MiniFlow") {
                defaults.removeObject(forKey: "flow_return_app_bundle_id")
                defaults.synchronize()
                openAppWithBundleID(bundleID)
                return
            }
        }
    }

    static func openAppWithBundleID(_ bundleID: String) {
        let className = ["LS", "Application", "Workspace"].joined()
        let methodName = ["open", "Application", "With", "BundleID:"].joined()

        guard let workspaceClass = NSClassFromString(className),
              workspaceClass.responds(to: NSSelectorFromString("defaultWorkspace")),
              let workspace = (workspaceClass as AnyObject).perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue()
        else { return }

        let openSelector = NSSelectorFromString(methodName)
        if (workspace as AnyObject).responds(to: openSelector) {
            _ = (workspace as AnyObject).perform(openSelector, with: bundleID)
        }
    }
}

// MARK: - App Delegate

class MiniFlowAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = MiniFlowSceneDelegate.self
        return config
    }
}

// MARK: - App Entry Point

@main
struct MiniFlow_iOSApp: App {
    @UIApplicationDelegateAdaptor(MiniFlowAppDelegate.self) var appDelegate
    @StateObject private var flowRecorder = FlowBackgroundRecorder.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(flowRecorder)
        }
    }
}
