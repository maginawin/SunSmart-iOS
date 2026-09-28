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

    // SceneDelegate owns the window; legacy HUD and window helpers share this reference.
    weak var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
    #if DEBUG
        PJUIDebugConsoleTracer.start()
    #endif
        LabSettings.applyOutgoingMeshTTLOverride()
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
        #elseif Lumineux
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区,默认欧洲服务器
            UserData.currentServerRegion = .europe
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
