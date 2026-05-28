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
    #if DEBUG
        PJUIDebugConsoleTracer.start()
    #endif
        window = UIWindow(frame: UIScreen.main.bounds)
        if UserData.isTermsOfService { // 是否同意使用协议
            let mainNavVc = NavigationViewController(rootViewController: SitesViewController())
            window?.rootViewController = mainNavVc
        }else {
            let welcomeNavVc = NavigationViewController(rootViewController: WelcomeViewController())
            window?.rootViewController = welcomeNavVc
        }
        // 禁用暗黑模式
        window?.overrideUserInterfaceStyle = .light
        window?.makeKeyAndVisible()
        
        SunSmartDataManager.shared.initDatabase()
        XWHUDManager.configHUDType(.light)
        Bugly.start(withAppId: "e4965156c7")
        
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

    func applicationWillTerminate(_ application: UIApplication) {
        SpaceDebugUARTManager.shared.resetAll()
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
        guard Thread.isMainThread else {
            return (delegate as? AppDelegate)?.window ?? UIWindow()
        }
        let windowScene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return windowScene?.windows.first(where: { $0.isKeyWindow })
            ?? windowScene?.windows.first
            ?? (delegate as? AppDelegate)?.window
            ?? UIWindow()
    }
}
