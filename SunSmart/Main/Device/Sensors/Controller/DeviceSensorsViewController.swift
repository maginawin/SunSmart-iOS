//
//  DeviceSensorsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/14.
//

import UIKit
import NordicSigMeshSDK

class DeviceSensorsViewController: UIViewController {
    
    
    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!
    
    private var footerView: SpaceFunctionFooterView!
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    
    let space: SpaceData
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = Background_Color
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateUI()
    }
    
    private func updateUI() {
        
        footerView.countBtn.setTitle("0/\(space.maxDevicesCount)", for: .normal)
//        if !space.deviceOperates.contains(.add) {
//            footerView.addBtn.isEnabled = false
//        }
//        if !space.deviceOperates.contains(.edit) {
//            footerView.editBtn.isEnabled = false
//        }
        footerView.addBtn.isEnabled = space.deviceOperates.contains(.add)
        footerView.editBtn.isEnabled = space.deviceOperates.contains(.edit)
        footerView.sortBtn.isHidden = true
        
        updateDevicesEmptyUI()
        
    }
    
    private func updateDevicesEmptyUI() {
        
        if true {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

            collectionView.showEmptyDataView(title: "no_sensors".localizedString, tipText: "no_sensors_message".localizedString, position: .center, bottomMargin: SCRYFit(30))
            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            footerView.editBtn.isEnabled = false
        }else {
//            headerView.isHidden = false
            collectionView.hideEmptyDataView()
            footerView.editBtn.isEnabled = !isEdit
        }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.enableTestDelete = true
        footerView.editBtn.isEnabled = false
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = columnNum
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
        //        UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: <#T##CGFloat#>, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(40 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: collectionViewMargin, right: collectionViewMargin)
        //        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: SCRYFrom(16), right: 0)
        collectionView.backgroundColor = Background_Color
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(DeviceAllOnOffViewCell.classForCoder(), forCellWithReuseIdentifier: "allControlCell")
        collectionView.alwaysBounceVertical = true
//        collectionView.dataSource = self
//        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
            //            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
            //            make.bottom.equalToSuperview()
        }
    }
    
    /// 长按事件，跳转到开关详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
//        let point = sender.location(in: collectionView)
//        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.switchs.count {
//            let switche = MeshNetworkManager.instance.switchs[indexPath.item]
//            let vc = DeviceSwitchViewController(space: self.space,switchData: switche)
//            present(NavigationViewController(rootViewController: vc), animated: true)
//        }
    }
    
}

extension DeviceSensorsViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        let point = CGPoint(x: view.addBtn.center.x, y: SCREEN_HEIGHT - footerView.height)
        (self.parent as? DevicesViewController)?.addAction(point: point)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        view.isEditing = false
        isEdit = true
        updateUI()
    }
}
