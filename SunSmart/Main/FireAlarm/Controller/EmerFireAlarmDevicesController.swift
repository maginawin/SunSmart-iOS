//
//  EmerFireAlarmDevicesController.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/22.
//

import UIKit
import NordicSigMeshSDK

let emerFireAlarmDevicesNotificationName = "emerFireAlarmDevices_notice"

class EmerFireAlarmDevicesController: UIViewController {

    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!
    
    private var footerView: SpaceFunctionFooterView!
    
    private var repairView: EmerFireAlarmDevicesRepairView!
    
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    let space: SpaceData
    
    var emerFireAlarmDevices : [String] = ["1","2","3","4","5","6"]
    
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
        
        addNotificationObserver()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(emerFireAlarmDevicesNotificationName), object: nil, queue: nil) {[weak self] _ in
            //            self?.refreshData = true
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }
        }
    }
    
    private func updateUI() {
        
        footerView.countBtn.setTitle("\(6)/\(space.maxDevicesCount)", for: .normal)
        footerView.addBtn.isEnabled = space.deviceOperates.contains(.add)
        footerView.editBtn.isEnabled = space.deviceOperates.contains(.edit)
        footerView.sortBtn.isHidden = true
        
        updateDevicesEmptyUI()
        self.collectionView.reloadData()
    }
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
          emerFireAlarmDevices.removeAll()
          updateDevicesEmptyUI()
    }
    
    
    private func updateDevicesEmptyUI() {
        
        if emerFireAlarmDevices.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }
            collectionView.showEmptyDataView(title: "no_others".localizedString, tipText: "no_others_message".localizedString, position: .center, bottomMargin: SCRYFit(30))
            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            footerView.editBtn.isEnabled = false
        }else {

            collectionView.hideEmptyDataView()
            footerView.editBtn.isEnabled = !isEdit
        }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.editBtn.isEnabled = false
        footerView.enableTestDelete = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        repairView = EmerFireAlarmDevicesRepairView()
        view.addSubview(repairView)

        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.register(EmerFireAlarmDeviceCell.self)
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
            make.bottom.equalTo(repairView.snp.top)
          
        }
        
        repairView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
            make.height.equalTo(SCRYFit(60))
        }
        view.bringSubviewToFront(repairView)
        repairView.repairCountLabel.text = String(format: "device_repair_tip".localizedString, 1)
        repairView.repairAction = {
            XWHUDManager.showTipHUD("device_repair", isLineFeed: false)
        }
    }
    
    /// 长按事件，跳转到开关详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point){
            XWHUDManager.showTipHUD("\(indexPath.row)", isLineFeed: false)
        }
    }
    

}

extension EmerFireAlarmDevicesController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        emerFireAlarmDevices.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: EmerFireAlarmDeviceCell = collectionView.dequeueReusableCell(for: indexPath)
        cell.configCell(name: "EFC\(indexPath.row + 1)", status: EmerFireStatus.allCases[indexPath.row])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat(columnNum - 1)) / CGFloat(columnNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        XWHUDManager.showTipHUD("didSelectItemAt\(indexPath.row)", isLineFeed: false)
    }
    
    
}

extension EmerFireAlarmDevicesController: SpaceFunctionFooterViewDelegate {
    
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
