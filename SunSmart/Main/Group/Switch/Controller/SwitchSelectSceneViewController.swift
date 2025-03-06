//
//  SwitchSelectSceneViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/13.
//

import UIKit
import NordicSigMeshSDK

class SwitchSelectSceneViewController: UIViewController {

    private var sceneTableView: UITableView!
    
    /// 选择的A场景
//    var sceneA: Scene?
//    /// 选择的B场景
//    var sceneB: Scene?
    /// 场景list
    let scenes: [Scene]
    /// 场景选择回调
    var sceneSelectCallback: ((_ sceneData: SwitchSceneData?)->Void)?
    /// 是否可以编辑
    var editable: Bool = true

    var sceneData: SwitchSceneData!
    
    init(scenes: [Scene], sceneData: SwitchSceneData) {
        
        self.scenes = scenes
//        self.sceneA = sceneA
//        self.sceneB = sceneB
        super.init(nibName: nil, bundle: nil)
        
        self.sceneData = sceneData
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
        
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        if scenes.isEmpty && sceneTableView.emptyView == nil {
            view.layoutIfNeeded()
            sceneTableView.showEmptyDataView(title: "no_scene".localizedString, tipText: "no_scenes_message".localizedString, margin: SCRXFrom(42))
            sceneTableView.emptyView?.backgroundColor = .clear
        }
    }
    
    private func setupUI() {
        
//        menuView = WMMenuView(frame: CGRect(x: 0, y: kNavigationHeight, width: view.width, height: SCRYFrom(45)))
//        menuView.progressHeight = 2
//        menuView.style = .line
//        menuView.progressWidths = [SCRXFrom(63.5)]
//        menuView.layoutMode = .center
//        menuView.lineColor = Bar_Color
//        menuView.progressViewBottomSpace = SCRYFrom(6)
//        menuView.dataSource = self
//        menuView.delegate = self
//        view.addSubview(menuView)
//        menuView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
//            make.top.equalTo(view.safeAreaLayoutGuide)
//            make.height.equalTo(SCRYFrom(45))
//        }
        
       
        sceneTableView = UITableView()
        sceneTableView.separatorStyle = .none
        sceneTableView.backgroundColor = .clear
        sceneTableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        sceneTableView.rowHeight = SCRYFrom(44)
        sceneTableView.dataSource = self
        sceneTableView.delegate = self
        view.addSubview(sceneTableView)
        sceneTableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
    }
    
}

//extension SwitchSelectSceneViewController: WMMenuViewDataSource, WMMenuViewDelegate {
//    
//    func numbersOfTitles(in menu: WMMenuView!) -> Int {
//        return titles.count
//    }
//    
//    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
//        return titles[index]
//    }
//    
//    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
//        return SCRXFrom(64)
//    }
//    
//    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
//        return SCRYFrom(15)
//    }
//    
//    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
//        return state == .selected ? Bar_Color : SubText_Color
//    }
//    
//    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
//        return index == 1 ? SCRXFrom(53) : 0
//    }
//    
//    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
//        
//        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * scrollView.width, y: 0), animated: true)
//    }
//    
//}

extension SwitchSelectSceneViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scenes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let scene = scenes[indexPath.row]
        cell.cellStyle = .icon
        cell.titleLabel.text = scene.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        let isSelect = sceneData.scene == scene
//        if tableView == sceneATableView {
//            isSelect = scene == sceneA
//        }else {
//            isSelect = scene == sceneB
//        }
        let selectImage = UIImage(named: isSelect ? "schedule_target_select" : "schedule_target_select_un")
        if self.editable {
            cell.iconImageView.image = selectImage
        }else {
            cell.iconImageView.image = selectImage?.withTintColor(RGB(216, 216, 216))
        }
        cell.iconX = tableView.width - 30 - SCRXFrom(8)
        cell.arrowImageView.isHidden = true
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard editable else {
            return
        }
        let scene = scenes[indexPath.row]
        if scene == sceneData.scene {
            sceneData.scene = nil
        }else {
            sceneData.scene = scene
        }
        
        
        tableView.reloadData()
        
        sceneSelectCallback?(sceneData)
    }
    
    
    
//    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        guard scrollView == self.scrollView else { return }
//        let progress = scrollView.contentOffset.x / scrollView.width
//        menuView.slideMenu(atProgress: progress)
//    }
    
}
