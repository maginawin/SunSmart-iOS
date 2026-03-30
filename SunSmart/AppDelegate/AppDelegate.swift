//
//  AppDelegate.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/8/21.
//

import UIKit
import NordicSigMeshSDK
import Bugly

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        window = UIWindow(frame: UIScreen.main.bounds)
        if UserData.isTermsOfService { // 是否同意使用协议
            if let site = SiteData.load(siteId: "D01FCBA3-B5CF-4B1E-9CF8-0A6E96E89922"), let space = site.spaces.first(where: { $0.id == "F2769094-8319-47DB-8874-E82057052B33" }) {
                let vc = SpacePathTriggerZoneController(site: site, space: space)
                let mainNavVc = NavigationViewController(rootViewController: vc)
                window?.rootViewController = mainNavVc
            }else {
                let mainNavVc = NavigationViewController(rootViewController: SitesViewController())
                window?.rootViewController = mainNavVc
            }
        }else {
            let welcomeNavVc = NavigationViewController(rootViewController: WelcomeViewController())
            window?.rootViewController = welcomeNavVc
        }
        // 禁用暗黑模式
        window?.overrideUserInterfaceStyle = .light
        window?.makeKeyAndVisible()
        
        SunSmartDataManager.shared.initDatabase()
        XWHUDManager.configHUDType(.light)
        
        Bugly.start(withAppId: "fce1e870b0")
        
        MeshLibManager.manager.disableRecyclingExclusions = true
        // 加载设备配置信息list（未加入配置的设备类型无法添加）
        let configInfos = MeshDeviceConfigInfo.load()
        if configInfos.count > 0 {
            MeshLibManager.manager.supportDeviceInfos = configInfos
        }
        
        #if Archipelago
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区
            UserData.currentServerRegion = .northAmerica
        }
        #elseif SylSmart
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区,默认亚太服务器
            UserData.currentServerRegion = .asiaPacific
        }
        #elseif SLGSync
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区,默认北美服务器
            UserData.currentServerRegion = .northAmerica
        }
        #endif
        NetworkRequest.shared.networkListener()
        
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
