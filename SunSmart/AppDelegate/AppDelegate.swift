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
        
        
        
//        let mainNavVc = NavigationViewController(rootViewController: GroupViewController(space: space!, group: space!.groups.first!)) //SitesViewController
        if UserData.isTermsOfService { // 是否同意使用协议
//            let site = SiteData.loadAll()[3]
//            let space = site.spaces[1]
//            let spaceVc = SpaceViewController(space: space)
//            spaceVc.site = site
//            let mainNavVc = NavigationViewController(rootViewController: spaceVc)
            
            let mainNavVc = NavigationViewController(rootViewController: SitesViewController())
//            let mainNavVc = NavigationViewController(rootViewController: MeshFirmwareUpdateViewController(distributorData: MeshDistributionData(distributionAddress: 0x01, targetAddresses: [0x01, 0x02], distributionState: .complete)))
            
            window?.rootViewController = mainNavVc
        }else {
            let welcomeNavVc = NavigationViewController(rootViewController: WelcomeViewController())
            window?.rootViewController = welcomeNavVc
        }
        
//        let mainNavVc = NavigationViewController(rootViewController: WelcomeViewController())
//        NavigationViewController(rootViewController: SitesViewController())
//        let mainNavVc = NavigationViewController(rootViewController: DeviceAddViewController())
        
//        let node = space?.meshManager?.meshNetwork?.nodes.first
        
        
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
