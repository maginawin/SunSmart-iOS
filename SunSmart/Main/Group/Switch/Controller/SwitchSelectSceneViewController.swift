//
//  SwitchSelectSceneViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/13.
//

import UIKit
import NordicSigMeshSDK

class SwitchSelectSceneViewController: UIViewController {

    private var menuView: WMMenuView!
    private var scrollView: PopGestureScrollView!
    private var sceneATableView: UITableView!
    private var sceneBTableView: UITableView!
    private var titles: [String] = ["scene_a".localizedString, "scene_b".localizedString]
    
    /// 选择的A场景
    var sceneA: Scene?
    /// 选择的B场景
    var sceneB: Scene?
    /// 场景list
    let scenes: [Scene]
    /// 场景选择回调
    var sceneSelectCallback: ((_ sceneA: Scene?, _ sceneB: Scene?)->Void)?
    
    init(scenes: [Scene], sceneA: Scene?, sceneB: Scene?) {
        self.scenes = scenes
        self.sceneA = sceneA
        self.sceneB = sceneB
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_scene".localizedString
        view.backgroundColor = Background_Color
        
        setupUI()
        
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        if scenes.isEmpty && sceneATableView.emptyView == nil {
            view.layoutIfNeeded()
            sceneATableView.showEmptyDataView(title: "no_scene".localizedString, tipText: "no_scenes_message".localizedString, margin: SCRXFrom(42))
            sceneATableView.emptyView?.backgroundColor = .clear
            
            sceneBTableView.showEmptyDataView(title: "no_scene".localizedString, tipText: "no_scenes_message".localizedString, margin: SCRXFrom(42))
            sceneBTableView.emptyView?.backgroundColor = .clear
        }
    }
    
    private func setupUI() {
        
        let menuY = navigationController?.navigationBar.height ?? kNavigationHeight
        menuView = WMMenuView(frame: CGRect(x: 0, y: menuY, width: view.width, height: SCRYFrom(45)))
        menuView.progressHeight = 2
        menuView.style = .line
        menuView.progressWidths = [SCRXFrom(63.5)]
        menuView.layoutMode = .center
        menuView.lineColor = Bar_Color
        menuView.progressViewBottomSpace = SCRYFrom(6)
        menuView.dataSource = self
        menuView.delegate = self
        view.addSubview(menuView)
        menuView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(menuY)
            make.height.equalTo(SCRYFrom(45))
        }
        
        scrollView = PopGestureScrollView()
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(menuView.snp.bottom).offset(SCRYFrom(10))
        }
        
        sceneATableView = UITableView()
        sceneATableView.separatorStyle = .none
        sceneATableView.backgroundColor = .clear
        sceneATableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        sceneATableView.rowHeight = SCRYFrom(44)
        sceneATableView.dataSource = self
        sceneATableView.delegate = self
        scrollView.addSubview(sceneATableView)
        sceneATableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        sceneBTableView = UITableView()
        sceneBTableView.separatorStyle = .none
        sceneBTableView.backgroundColor = .clear
        sceneBTableView.dataSource = self
        sceneBTableView.delegate = self
        sceneBTableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        sceneBTableView.rowHeight = SCRYFrom(44)
        scrollView.addSubview(sceneBTableView)
        sceneBTableView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(sceneATableView.snp.right)
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
    }
    
}

extension SwitchSelectSceneViewController: WMMenuViewDataSource, WMMenuViewDelegate {
    
    func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return titles.count
    }
    
    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return titles[index]
    }
    
    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        return SCRXFrom(64)
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return SCRYFrom(15)
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? Bar_Color : SubText_Color
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        return index == 1 ? SCRXFrom(53) : 0
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        
        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * scrollView.width, y: 0), animated: true)
    }
    
}

extension SwitchSelectSceneViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scenes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let scene = scenes[indexPath.row]
        cell.cellStyle = .icon
        cell.titleLabel.text = scene.info.name ?? scene.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        var isSelect = false
        if tableView == sceneATableView {
            isSelect = scene == sceneA
        }else {
            isSelect = scene == sceneB
        }
        cell.iconImageView.image = UIImage(named: isSelect ? "schedule_target_select" : "schedule_target_select_un")
        cell.iconX = tableView.width - 30 - SCRXFrom(8)
        cell.arrowImageView.isHidden = true
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let scene = scenes[indexPath.row]
        
        if tableView == sceneATableView {
            if sceneA == scene {
                sceneA = nil
            }else {
                sceneA = scene
            }
        }else {
            if sceneB == scene {
                sceneB = nil
            }else {
                sceneB = scene
            }
        }
        
        tableView.reloadData()
        
        sceneSelectCallback?(sceneA, sceneB)
    }
    
    
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.scrollView else { return }
        let progress = scrollView.contentOffset.x / scrollView.width
        menuView.slideMenu(atProgress: progress)
    }
    
}
