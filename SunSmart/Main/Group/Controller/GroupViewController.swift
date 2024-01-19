//
//  GroupViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit
import NordicSigMeshSDK

class GroupViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var onoffBtn: UIButton!
    private var lightnessSlider: BuoySliderView!
    private var cctSlider: BuoySliderView!
    private var pageControl: UIPageControl!
    
    let space: SpaceData
    let group: Group
    
//    private var devices: [String] = []
    private var isGroupUpdateData = false
    /// 组更新回调
//    var groupUpdateCallback: ((Group)->Void)?
    /// 组删除回调
//    var groupDeleteCallback: ((Group)->Void)?
    
    init(space: SpaceData,group: Group) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = group.name
        
        view.backgroundColor = Background_Color
        
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            
            navigationController?.setNavigationBarBackgroundColor(color: .clear)
            
//            let appearance = UINavigationBarAppearance()
//            appearance.configureWithOpaqueBackground()
//            appearance.backgroundColor = .clear
//            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
////            appearance.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 18, weight: .light)]
//            navigationController?.navigationBar.standardAppearance = appearance
//            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        bindSliderAciton()
        
//        for i in 1...30 {
//            devices.append("ID \(i)")
//        }
    
        addNotificationObserver()
        
        updateUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        collectionView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isGroupUpdateData {
            NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(2) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(3)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW)
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            var height = itemSize.height * 3.0 + flowLayout.minimumLineSpacing * 2.0 + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
            height = CGFloat(ceilf(Float(height)))
//            CGFloat(floorf(Float(height) * 100) / 100.0)
            make.height.equalTo(height)
        }
        
    }
    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            //            self?.refreshData = true
            guard let self = self, let group = notification.object as? Group else { return }
        
            self.title = group.name
            self.updateUI()
        }
        
    }
    
    @objc private func close() {
        dismiss(animated: true)
    }
    
    private func updateUI() {
        pageControl.numberOfPages = Int(ceil(Double(group.nodes.count) / 9.0))
//        pageControl.currentPage = 0
        updateEmptyUI()
        
        onoffBtn.isSelected = group.isOn
        lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
        cctSlider.value = group.cct
        
        collectionView.reloadData()
    }
    
    private func updateEmptyUI() {
        if group.nodes.isEmpty {
            if collectionView.frame == .zero {
                view.layoutIfNeeded()
            }
            collectionView.showEmptyDataView(title: "no_members".localizedString, position: .center, bottomMargin: 3.5)
        }else {
            collectionView.hideEmptyDataView()
        }
    }
    
    @objc private func moreClick() {
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                self?.editGroup()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
//                self?.deleteSite()
                self?.deleteGroup()
            }),
            .init(icon: UIImage(named: "menu_members"), title: "members".localizedString, tapItemBack: {[weak self] item in
                self?.members()
            }),
            .init(icon: UIImage(named: "menu_profile"), title: "profile".localizedString, tapItemBack: {[weak self] item in
                self?.groupProfile()
            })
            
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight) + 44))
        
    }
    
    @objc private func onoffBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: sender.isSelected)
        group.isOn = sender.isSelected
        group.nodes.forEach({
            $0.isOn = group.isOn
        })
        collectionView.reloadData()
        isGroupUpdateData = true
    }
    
    private func bindSliderAciton() {
        lightnessSlider.valueChangedCallback = {[weak self] (value, ended) in
            print("lightness: \(value)")
            guard let self = self else { return }
            let lightness = Node.getLightness(lightness100: value)
            self.group.lightness = lightness
            MeshAPI.setGroupLightnessState(address: self.group.address.address, lightness: lightness)
            group.nodes.forEach({
                $0.isOn = lightness > 0
                $0.lightness = lightness
//                self.reloadCollectionItem(node: $0)
            })
            collectionView.reloadData()
            self.isGroupUpdateData = true
        }
        
        cctSlider.valueChangedCallback = {[weak self] (value, ended) in
            print("cct: \(value)")
            guard let self = self else { return }
            self.group.cct = value
            MeshAPI.setGroupColorTemperatureState(address: self.group.address.address, temperature: UInt16(value))
            group.nodes.forEach({
                $0.temperature = UInt16(value)
//                self.reloadCollectionItem(node: $0)
            })
            collectionView.reloadData()
            self.isGroupUpdateData = true
        }
    }
    
    /// 编辑组
    private func editGroup() {
        
        let editVc = GroupAddViewController(space: space, group: group)
//        editVc.doneCallback = {[weak self] group in
//            self?.title = group.name
//            self?.groupUpdateCallback?(group)
//        }
        let navVc = NavigationViewController(rootViewController: editVc)
        present(navVc, animated: true)
    }
    
    /// 删除组
    private func deleteGroup() {
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, contentPadding: SCRXFrom(25), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            
            guard self.group.nodes.isEmpty || self.group.nodes.contains(where: { $0.state }) else { // 设备是否都在线
                SRAlertView(title: "notification".localizedString, message: "group_delete_offline".localizedString, actions:[SRAlertAction(title: "confirm".localizedString, actionHandler: nil)]).show()
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            
            group.nodes.forEach({ node in
                node.unsubscribe(from: self.group)
                node.sceneDatas.removeAll()
                // 删除设备场景数据
                SceneExecuteData.deleteData(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress)
                // 删除设备关联组的日程数据
                self.group.info.bindSchedules.forEach{ schedule in
                    Node.deleteSchedule(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress, scheduleId: schedule.id)
                }
            })
            
            GroupServer.deleteGroup(group: self.group, progress: nil) {[weak self] _ in
                XWHUDManager.hide()
                guard let self = self else { return }
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                NotificationCenter.default.post(name: .init(groupsRefreshNotificationName), object: nil)
//                self.groupDeleteCallback?(self.group)
                self.close()
                
            } failed: {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("group_delete_failed".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    XWHUDManager.hide()
                    // 跳转到检查页面
                    self?.deleteFailedCheck()
                }
            }
            
        })]).show()
        
    }
    
    /// 删除失败去手动同步
    private func deleteFailedCheck() {
        
        let vc = SyncDevicesViewController(type: .group(group, outNodes: group.nodes))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            GroupServer.deleteGroup(group: group, progress: nil, successful: nil, failed: nil)
            self.isGroupUpdateData = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.close()
            }
        }
//        present(NavigationViewController(rootViewController: vc), animated: true)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    /// 查看成员
    private func members() {
        
        let vc = GroupMembersViewController(space: space, group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 配置文件
    private func groupProfile() {
        
        let vc = GroupProfilesViewController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }
    
    /// 刷新设备
    private func reloadCollectionItem(node: Node) {
        
        if let index = space.nodes.firstIndex(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = node
            }
        }
    }
    
    /// 长按事件，跳转到设备详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < group.nodes.count {
            let node = group.nodes[indexPath.item]
            let vc = DeviceLightViewController(space: space, node: node)
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    
    private func setupUI() {
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(14)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(24), bottom: 0, right: SCRXFrom(24))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: 0, bottom: SCRYFrom(36), right: 0)
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(GroupDeviceViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(SCRYFit(40) + (navigationController?.navigationBar.frame.maxY ?? 0))
            make.height.equalTo(SCRYFrom(340))
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }
        
        onoffBtn = UIButton(normalImageName: "group_off", selectedImageName: "group_on", target: self, action: #selector(onoffBtnClick))
        view.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(32))
            make.centerX.equalToSuperview()
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.5
//        lightnessSlider.isHidden = !group.supportLightness
        view.addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.right.equalTo(collectionView)
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(8))
            make.height.equalTo(SCRYFrom(76))
        }
        
        cctSlider = BuoySliderView(frame: .zero, functionType: .cct())
        cctSlider.slider.interval = 0.5
//        Node.getTemperature100(temperature: UInt16(group.cct))
//        cctSlider.isHidden = !group.supportCct
        view.addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightnessSlider)
            make.top.equalTo(lightnessSlider.snp.bottom).offset(SCRYFit(2))
        }
        
    }


}

extension GroupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return group.nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupDeviceViewCell
        let node = group.nodes[indexPath.item]
        cell.device = node
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = space.nodes[indexPath.item]
        node.isOn = !node.isOn
        if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
            node.trunOffLightness = node.lightness
        }
        
        reloadCollectionItem(node: node)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//
//    }
    
}
