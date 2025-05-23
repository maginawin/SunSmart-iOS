//
//  GroupPathSequenceTriggerAddView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit
import NordicSigMeshSDK

protocol GroupPathSequenceTriggerAddViewDelegate: AnyObject {
    
    /// 识别设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, identifyDevice device: Node)
    
    /// 选择设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, selectDevice device: Node)
    
    /// 是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, showAddedDevicesChanged showAdded: Bool)

}

class GroupPathSequenceTriggerAddView: UIView {
    
    private var titleLabel: UILabel!
    private var switchBtn: UIButton!
    private var flowLayout: HorizontalDirectionFlowLayout!
    private var collectionView: UICollectionView!
    private var pageControl: UIPageControl!
    private var noDevicesLabel: UILabel!
    
    let colCount: Int = 5
    
    var guideView: GroupPathSequenceDeviceAddStepView!
    
    weak var delegate: GroupPathSequenceTriggerAddViewDelegate?
    var showAdded: Bool = false
    
    /// 选中的设备
    private(set) var selectDevice: Node?
    var isSequence: Bool = true
    
    private(set) var devices: [Node] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func reloadData(devices: [Node], selectDevice: Node?) {
        self.devices = devices
        self.selectDevice = selectDevice
        
        noDevicesLabel.isHidden = devices.count > 0
        collectionView.reloadData()
        pageControl.numberOfPages = Int(ceilf(Float(devices.count) / Float(colCount)))
    }

    @objc private func switchBtnAction(sender: UIButton) {
        let menuWidth = SCRXFrom(256)
        let btnPoint = CGPoint(x: self.width - menuWidth, y: sender.frame.maxY)
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())
        var titles = ["trigger_add_hide_added_devices".localizedString, "trigger_add_show_added_devices".localizedString]
        if !isSequence {
            titles = [
                "trigger_add_hide_added_devices".localizedString,
                "zone_trigger_add_show_added_devices".localizedString
            ]
        }
      
        TitleSelectView.show(titles: titles, style: .default, anchorPoint: windowPoint, menuWidth: menuWidth, itemHeight: SCRYFrom(44), titleFont: UIFont.systemFont(ofSize: 14, weight: .light)) {[weak self] index in
            guard let self = self else { return }
            self.titleLabel.text = titles[index]
            
            self.showAdded = index == 1
            self.delegate?.triggerAddView(self, showAddedDevicesChanged: self.showAdded)
        }
        
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "trigger_add_hide_added_devices".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-60))
        }
        
        switchBtn = UIButton(normalImageName: "arrow_down_black", target: self, action: #selector(switchBtnAction))
        addSubview(switchBtn)
        switchBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(4))
        }
        
        flowLayout = HorizontalDirectionFlowLayout()
        flowLayout.itmeColCount = 5
        flowLayout.itemRowCount = 1
        flowLayout.minimumInteritemSpacing = SCRXFrom(18)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(26), bottom: 0, right: SCRXFrom(25))
        collectionView.register(GroupPathSequenceAddDeviceCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(SCRYFrom(50))
            make.height.equalTo(SCRYFrom(44))
        }
        
        noDevicesLabel = UILabel(text: "filter_no_devices".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
//        noDevicesLabel.isHidden = true
        addSubview(noDevicesLabel)
        noDevicesLabel.snp.makeConstraints { make in
            make.center.equalTo(collectionView)
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.hidesForSinglePage = true
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-8))
            make.height.equalTo(SCRYFrom(6))
        }
        
        guideView = GroupPathSequenceDeviceAddStepView()
        guideView.step3View.titleLabel.text = "path_trigger_add_step3".localizedString
        guideView.isHidden = true
        addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
    }
}

extension GroupPathSequenceTriggerAddView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return devices.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupPathSequenceAddDeviceCell
        let node = devices[indexPath.item]
        cell.nameLabel.text = node.name
        if node == selectDevice {
            cell.layer.borderColor = Yellow_Color.cgColor
        }else {
            cell.layer.borderColor = RGB(241, 242, 244).cgColor
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(colCount - 1)) / CGFloat(colCount)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let device = devices[indexPath.item]
        if device == selectDevice {
            delegate?.triggerAddView(self, selectDevice: device)
        }else {
            selectDevice = device
            delegate?.triggerAddView(self, identifyDevice: device)
        }
        selectDevice = device
        collectionView.reloadData()
    }
    
    
}
