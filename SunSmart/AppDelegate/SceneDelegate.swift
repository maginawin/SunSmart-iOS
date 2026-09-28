import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        // Register before loading the root controller so legacy UI uses this scene's window.
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
        window.overrideUserInterfaceStyle = .light

        let rootViewController: UIViewController
        if UserData.isTermsOfService {
            rootViewController = SitesViewController()
        } else {
            rootViewController = WelcomeViewController()
        }
        window.rootViewController = NavigationViewController(rootViewController: rootViewController)
        window.makeKeyAndVisible()

        #if DEBUG
        print("[AppLifecycle] scene connected root=\(type(of: rootViewController))")
        #endif
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let window,
              appDelegate.window === window else { return }
        appDelegate.window = nil
    }
}
