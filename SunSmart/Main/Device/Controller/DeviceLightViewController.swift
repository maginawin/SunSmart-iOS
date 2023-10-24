//
//  DeviceLightViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/16.
//

import UIKit
import NordicSigMeshSDK

class DeviceLightViewController: WMPageController {

    let space: SpaceData
    let node: Node
    
    private var lightBasicVc: DeviceLightBasicController?
    
    private var pageTitles: [String] = ["basic".localizedString, "advanced".localizedString]
    
    init(space: SpaceData, node: Node) {
        self.space = space
        self.node = node
        super.init(nibName: nil, bundle: nil)
//        self.viewControllerClasses = [SpaceDevicesViewController.self, SpaceGroupsViewController.self]
        self.titleFontName = FontName_Medium
        self.titleSizeNormal = SCRYFrom(14)
        self.titleSizeSelected = SCRYFrom(16)
        self.titleColorNormal = RGB(156, 167, 175)
        self.titleColorSelected = Bar_Color
        self.menuViewStyle = .line
        self.progressHeight = 2
        self.progressColor = Bar_Color
        self.progressWidth = SCRXFrom(120)
        self.menuItemWidth = SCRXFrom(168)
//        self.itemMargin = 0
//        self.menuViewContentMargin = SCRXFrom(20)
        self.menuViewLayoutMode = .center
        self.scrollEnable = false
    }
    
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = node.name
        view.backgroundColor = Background_Color

        
        menuView?.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
    }
    
    @objc private func moreClick() {
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                self?.editNode()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
                self?.deleteNode()
            }),
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: kNavigationHeight))
    }
    
    /// 编辑设备
    private func editNode() {
        
        SRAlertView(title: "edit_name".localizedString, inputText: node.name, placeholder: "", actions: [.cancelAction, .init(title: "done".localizedString, style: .default)]) {[weak self] text, validRange in
//            guard let self = self else { return }
             if !validRange && !text.isEmpty { // 长度超限
                 return "text_length_exceeded".localizedString
             }else if (self?.space.isNodeTautonym(nodeName: text) ?? false) && text != self?.node.name { // 重名
                 return "name_already_exists".localizedString
             }
             return nil
         } inputDoneBack: {[weak self] text in
             guard let self = self else { return }
             self.title = text
             self.node.name = text
             _ = self.space.meshManager?.save()
             self.space.save()
             self.lightBasicVc?.reloadNodeName(text)
//             reloadNodeName
             
         }.show()
    }
    
    /// 删除设备
    private func deleteNode() {
        
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindiw: true)
            
            MeshAPI.resetNode(address: self.node.primaryUnicastAddress) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.space.save()
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                    self?.navigationController?.popViewController(animated: true)
                }
            } resetFail: { _, error in
                XWHUDManager.hide()
                
                let alertView = SRAlertView(title: "notification".localizedString, actions: [.cancelAction, SRAlertAction(title: "force_delete".localizedString, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    self.space.meshManager?.meshNetwork?.remove(node: self.node)
                    _ = self.space.meshManager?.save()
                    self.space.save()
                    self.navigationController?.popViewController(animated: true)
                })])
                let messageAttStr = NSMutableAttributedString(string: "device_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
                messageAttStr.append(NSAttributedString(string: "device_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
                alertView.messageLabel.attributedText = messageAttStr
                alertView.show()
            }
            
        })]).show()
        
    }

}

extension DeviceLightViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        if node.isKeybindComplete {
            return pageTitles.count
        }
        return 1
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        switch index {
        case 0:
            let vc = DeviceLightBasicController(node: node)
            lightBasicVc = vc
            return vc
        default:
            return DeviceLightAdvancedController(node: node)
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        var y = kNavigationHeight
        if node.isKeybindComplete {
            y += SCRYFrom(44)
        }
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        if node.isKeybindComplete {
            return CGRect(x: 0, y: kNavigationHeight, width: view.width, height: SCRYFrom(44))
        }
        return .zero
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return pageTitles[index]
    }

    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return true
//        return index < 3
    }
    
}
