//
//  AppDelegate.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/21.
//

import UIKit
import NordicSigMeshSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        window = UIWindow(frame: UIScreen.main.bounds)
        
        
//        let space = SiteData.loadAll()[0].spaces.last
//        let mainNavVc = NavigationViewController(rootViewController: SpaceViewController(space: space!)) //SitesViewController
        let mainNavVc = NavigationViewController(rootViewController: SitesViewController())
//        let mainNavVc = NavigationViewController(rootViewController: DeviceAddViewController())
        
//        let node = space?.meshManager?.meshNetwork?.nodes.first
        
        window?.rootViewController = mainNavVc
        window?.makeKeyAndVisible()
        
        SiteData.createDatabaseIfNotExit()
        XWHUDManager.configHUDType(.light)
        
//        UIApplication.shared.statusBarStyle = .default
        
        if #available(iOS 15.0, *) {
            UITableView.appearance().sectionHeaderTopPadding = 0
        }

        return true
    }

    // MARK: UISceneSession Lifecycle
//
//    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
//        // Called when a new scene session is being created.
//        // Use this method to select a configuration to create the new scene with.
//        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
//    }
//
//    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
//        // Called when the user discards a scene session.
//        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
//        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
//    }


}


extension UIApplication {
    func keyWindow() -> UIWindow {
        return UIApplication.shared.windows.first(where: {$0.isKeyWindow})!
    }
}
