//
//  DaliMasterMultipleControlsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/27.
//

import UIKit
import NordicSigMeshSDK

protocol DaliMasterMultipleControlsViewDelegate: AnyObject {
   
    //************ Dali主机 *************/
    /// dali主机onoff事件 isOn: 开/关
    func view(_ view: DaliMasterMultipleControlsView, masterOnOffAction isOn: Bool)
    /// dali主机亮度修改事件 value: 亮度百分比 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterMultipleControlsView, masterLightnessValueChanged value: Int, throttle: Bool, ended: Bool)
    /// dali主机色温修改事件 cct: 色温 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterMultipleControlsView, masterCctValueChanged cct: Int, throttle: Bool, ended: Bool)
    /// dali主机扫描dali设备
    func daliMasterDidScanDevices(view: DaliMasterMultipleControlsView)
    
    //************ Dali设备 *************/
    /// dali设备开关事件 isOn: 开/关
    func view(_ view: DaliMasterMultipleControlsView, daliOnOffAction isOn: Bool)
    /// dali设备详情
    func view(_ view: DaliMasterMultipleControlsView, daliDeviceDetails device: Node)
}

class DaliMasterMultipleControlsView: UIView {
    
    /// 列表
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    /// 分页
    private var pageControl: UIPageControl!
    /// 开关
    private var onoffBtn: UIButton!
    /// 亮度值
    private var brightnessView: LightFunctionItem!
    /// 亮度滑条
    private var lightnessSlider: BuoySliderView!
    /// 色温值
    private var cctView: LightFunctionItem!
    /// 色温滑条
    private var cctSlider: BuoySliderView!
    
    /// 列数
    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFrom(36), right: SCRXFrom(24))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    
    weak var delegate: DaliMasterMultipleControlsViewDelegate?
    
    /// 是否可编辑
    var editable: Bool = true {
        didSet {
            if let emptyView = collectionView.emptyView {
                emptyView.button.isHidden = !editable
            }
        }
    }
    
    var nodes: [Node] = [] {
        didSet {
            collectionView.reloadData()
            updateUI()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(rowNum - 1) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(rowNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW)
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            var height = itemSize.height * CGFloat(columnNum) + flowLayout.minimumLineSpacing * CGFloat(columnNum - 1) + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
            height = CGFloat(ceil(Float(height)))
//            CGFloat(floorf(Float(height) * 100) / 100.0)
            make.height.equalTo(height)
        }
        
        updateEmptyUI()
    }
    
    private func updateUI() {
        
        
        
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        
        if nodes.isEmpty {
            if collectionView.frame == .zero {
                self.layoutIfNeeded()
            }
            if collectionView.emptyView == nil {
                collectionView.showEmptyDataView(title: "no_bus_devices".localizedString, buttonText: "Scan_Dali_Devices".localizedString, position: .center) {[weak self] in
                    print("扫描dali设备")
                    guard let self = self else { return }
                    self.delegate?.daliMasterDidScanDevices(view: self)
                }
                if let emptyView = collectionView.emptyView {
                    if editable {
                        emptyView.button.backgroundColor = .clear
                        //                    emptyView.button.setTitle("add_member".localizedString, for: .normal)
//                            emptyView.button.setImage(UIImage(named: "member_add"), for: .normal)
                        emptyView.button.titleLabel?.font = FONTS(16)
                        emptyView.button.setTitleColor(Bar_Color, for: .normal)
                        emptyView.button.setImagePosition(position: .left, spacing: SCRXFrom(2))
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                        }
                    }else {
                        emptyView.button.isHidden = true
                    }
                }
            }
        }else {
            collectionView.hideEmptyDataView()
        }
        
    }
    
    // MARK: - Action
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }
    
    /// 刷新设备
    private func reloadCollectionItem(node: Node) {
        
        if let index = nodes.firstIndex(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = node
            }
        }
        
//        onoffBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && group.nodes.contains(where: { $0.state })
//        if group.isOn != onoffBtn.isSelected {
//            lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
//        }
//        onoffBtn.isSelected = group.isOn
//        cctSlider.value = group.cct
    }
    
    /// 长按事件，跳转到设备详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < nodes.count {
            let node = nodes[indexPath.item]
//            let vc = DeviceLightViewController(space: space, node: node)
//            navigationController?.pushViewController(vc, animated: true)
            delegate?.view(self, daliDeviceDetails: node)
        }
    }
    
    @objc private func onoffBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        delegate?.view(self, masterOnOffAction: sender.isSelected)
        
//        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: sender.isSelected)
//        node.isOn = sender.isSelected
//        group.nodes.forEach({
//            $0.isOn = group.isOn
//        })
//        lightnessSlider.value = group.isOn ? Node.getLightness100(lightness: group.lightness) : 0
//        collectionView.reloadData()
//        isGroupUpdateData = true
    }
    
    private func bindSliderAction() {
        
        lightnessSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            
            self.brightnessView.itemValueLabel.text = "\(value)%"
            
            self.delegate?.view(self, masterLightnessValueChanged: value, throttle: false, ended: false)
//            let lightness = Node.getLightness(lightness100: value)
//
//            if value == 0 {
//                self.node.trunOffLightness = self.node.lightness
//            }
//
//            self.node.lightness = lightness
//            self.node.isOn = lightness > 0
//            self.updateData()
        }
        lightnessSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
//            let lightness = Node.getLightness(lightness100: value, range: self.node.lightnessRange)
//            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ended)
            self.delegate?.view(self, masterLightnessValueChanged: value, throttle: true, ended: ended)
        }
        
        cctSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
//            self.node.temperature = UInt16(value)
//            self.updateData()
            self.cctView.itemValueLabel.text = "\(value)K"
            
            self.delegate?.view(self, masterCctValueChanged: value, throttle: false, ended: false)
        }
        cctSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
//            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: UInt16(value), ack: ended)
            self.delegate?.view(self, masterCctValueChanged: value, throttle: true, ended: ended)
        }
    }
    
    
    
    private func setupUI() {
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemRowCount = rowNum
        flowLayout.itmeColCount = columnNum
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: collectionViewInsets.left, bottom: 0, right: collectionViewInsets.right)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: collectionViewInsets.bottom, left: 0, bottom: collectionViewInsets.bottom, right: 0)
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(DaliDevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            if isIPad {
                make.top.equalTo(SCRYFit(60) + 56)
                make.height.equalTo(SCRYFrom(498))
            }else {
                make.top.equalTo(SCRYFit(40) + 56)
                make.height.equalTo(SCRYFrom(340))
            }
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }
        
        var offImageName = "group_off"
        var onImageName = "group_on"
        var disableImageName = "group_control_disable"
        if isIPad {
            offImageName = "group_off_big"
            onImageName = "group_on_big"
            disableImageName = "group_control_disable_big"
        }
        onoffBtn = UIButton(normalImageName: offImageName, selectedImageName: onImageName, target: self, action: #selector(onoffBtnClick))
        onoffBtn.setImage(UIImage(named: disableImageName), for: .disabled)
        addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            if isIPad {
                make.width.height.equalTo(56)
                make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(64))
            }else {
                make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(32))
            }
            make.centerX.equalToSuperview()
        }
        
        brightnessView = LightFunctionItem(imageName: "device_brightness", valueStr: "100%")
        addSubview(brightnessView)
        brightnessView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(40))
            make.centerY.equalTo(onoffBtn)
//            make.height.greaterThanOrEqualTo(SCRYFrom(20))
        }
        
        cctView = LightFunctionItem(imageName: "device_cct", valueStr: "4500K")
        addSubview(cctView)
        cctView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-40))
            make.centerY.equalTo(brightnessView)
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.5
//        lightnessSlider.isHidden = !group.supportLightness
        addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.right.equalTo(collectionView)
            }
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(8))
            make.height.equalTo(SCRYFrom(76))
        }
        
        cctSlider = BuoySliderView(frame: .zero, functionType: .cct())
        cctSlider.slider.interval = 0.5
        cctSlider.slider.step = 10
//        Node.getTemperature100(temperature: UInt16(group.cct))
//        cctSlider.isHidden = !group.supportCct
        addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightnessSlider)
            make.top.equalTo(lightnessSlider.snp.bottom).offset(SCRYFit(2))
        }
        
    }
    
}

extension DaliMasterMultipleControlsView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 26
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DaliDevicesViewCell
//        let node = nodes[indexPath.item]
        cell.iconImageView.image = UIImage(named: "dali_dt6")
        cell.progressView.progress = 70
//        cell.device = node
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = nodes[indexPath.item]
        node.isOn = !node.isOn
        delegate?.view(self, daliOnOffAction: node.isOn)
        
//        if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
//            node.trunOffLightness = node.lightness
//        }
//        if node.isOn {
//            node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
//        }else {
//            node.lightness = 0
//        }
//        reloadCollectionItem(node: node)
//        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
    
}
