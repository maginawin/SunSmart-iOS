//
//  SwitchSelectScenePageController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/3/4.
//

import UIKit
import NordicSigMeshSDK

struct SwitchSceneData {
    enum SceneType {
        var title: String {
            title(style: .lettered)
        }

        func title(style: SwitchSelectScenePageController.TitleStyle) -> String {
            switch style {
            case .lettered:
                switch self {
                case .sceneA:
                    return "switch_key_sceneA".localizedString
                case .sceneB:
                    return "switch_key_sceneB".localizedString
                case .sceneC:
                    return "switch_key_sceneC".localizedString
                case .sceneD:
                    return "switch_key_sceneD".localizedString
                }
            case .numbered:
                switch self {
                case .sceneA:
                    return "neightkeyswitches_scene_1".localizedString
                case .sceneB:
                    return "neightkeyswitches_scene_2".localizedString
                case .sceneC:
                    return "neightkeyswitches_scene_3".localizedString
                case .sceneD:
                    return "neightkeyswitches_scene_4".localizedString
                }
            }
        }

        case sceneA
        case sceneB
        case sceneC
        case sceneD
    }
    
    let type: SceneType
    var scene: Scene?
}

class SwitchSelectScenePageController: WMPageController {

    enum TitleStyle {
        case lettered
        case numbered
    }

    /// 场景list
    let scenes: [Scene]
    /// 场景选择回调
    var scenesSelectCallback: (([SwitchSceneData])->Void)?
    
    var sceneDatas: [SwitchSceneData]!
    let titleStyle: TitleStyle
    
    init(scenes: [Scene], sceneDatas: [SwitchSceneData] = [.init(type: .sceneA), .init(type: .sceneB)], titleStyle: TitleStyle = .lettered) {
        self.scenes = scenes
        self.titleStyle = titleStyle
//        self.sceneA = sceneA
//        self.sceneB = sceneB
        super.init(nibName: nil, bundle: nil)
        self.sceneDatas = sceneDatas
        
        self.menuViewStyle = .line
        self.progressHeight = 2
        self.progressWidth = SCRXFrom(63.5)
        self.menuViewLayoutMode = .center
        self.progressColor = Bar_Color
        self.progressViewBottomSpace = SCRYFrom(6)
        self.titleSizeNormal = 15
        self.titleSizeSelected = 15
        self.titleColorNormal = SubText_Color
        self.titleColorSelected = Bar_Color
        self.menuItemWidth = SCRXFrom(64)
        self.itemMargin = SCRXFrom(20)
    }
    
//    init() {
//        super.init(nibName: nil, bundle: nil)
//        
////        self.menuViewStyle = .flood
//        if isIPad {
//            self.menuViewLayoutMode = .center
//            self.itemMargin = SCRXFrom(24)
//        }
//        self.menuItemBackgroundColor = .clear
//    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_scene".localizedString
        view.backgroundColor = Background_Color

    }
    

}

extension SwitchSelectScenePageController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return self.sceneDatas.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        let sceneData = sceneDatas[index]
        
        let vc = SwitchSelectSceneViewController(scenes: scenes, sceneData: sceneData)
        vc.sceneSelectCallback = {[weak self] data in
            guard let self = self else { return }
            self.sceneDatas[index].scene = data?.scene
            self.scenesSelectCallback?(self.sceneDatas)
        }
        return vc
//        switch index {
//        case 0:
//            let vc = DevicesViewController(space: space)
//            return vc
//        case 1:
//            let vc = GroupsViewController(space: space)
//            return vc
//        case 2:
//            let vc = ScenesViewController(space: space)
//            return vc
//        case 3:
//            let vc = TimedViewController(space: space)
//            return vc
//        case 4:
//            let vc = SpaceMoreViewController(space: space)
//            return vc
//        default:
//            return UIViewController()
//        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(45)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top, width: view.width, height: SCRYFrom(45))
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return self.sceneDatas[index].type.title(style: titleStyle)
    }
    
//    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
//        mainMenuView.selectIndex = Int(self.selectIndex)
//        if let disablePageIndex = self.disablePageIndex, selectIndex == disablePageIndex {
//            self.scrollEnable = false
//        }
//    }
    
    
//    override func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
//        super.menuView(menu, didSelectedIndex: index, currentIndex: currentIndex)
//        
//        if let disablePageIndex = self.disablePageIndex, index == disablePageIndex {
//            self.scrollEnable = false
//        }else {
//            self.scrollEnable = true
//        }
//    }
    
}
