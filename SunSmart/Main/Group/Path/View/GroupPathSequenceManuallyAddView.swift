//
//  GroupPathSequenceManuallyAddView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/24.
//

import UIKit
import NordicSigMeshSDK

protocol GroupPathSequenceManuallyAddViewDelegate: AnyObject {
    
    /// 识别设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, identifyDevice device: Node)
    
    /// 选择设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, selectDevice device: Node)
 
    /// 是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, showAddedDevicesChanged showAdded: Bool)
}

class GroupPathSequenceManuallyAddView: UIView {
    private let topContentInset = SCRYFrom(8)
    
    private var helpImageView: UIImageView!
    private var groupFilterView: UIView!
    private var groupTitleLabel: UILabel!
    private var groupArrowImageView: UIImageView!
    private var titleLabel: UILabel!
    private var addTypeView: UIView!
    private var arrowImageView: UIImageView!
    private var flowLayout: HorizontalDirectionFlowLayout!
    private var collectionView: UICollectionView!
    private var pageControl: UIPageControl!
    private var noDevicesLabel: UILabel!
    /// 每行几个
    let colNum: Int = isIPad ? 8 : 5

    /// 行数
    var rowNum: Int = 1 {
        didSet {
            flowLayout.itemColCount = rowNum
            
            collectionView.snp.updateConstraints { make in
                make.height.equalTo(currentCollectionHeight())
            }
            
            pageControl.numberOfPages = Int(ceilf(Float(devices.count) / Float(colNum * rowNum)))
            UIView.animate(withDuration: 0.25) {
                self.superview?.layoutIfNeeded()
            }
            collectionView.reloadData()
        }
    }
    
    var guideContentView: UIView!
    var guideView: GroupPathSequenceDeviceAddStepView!
    
    
    weak var delegate: GroupPathSequenceManuallyAddViewDelegate?
    var showAdded: Bool = false
    var usesCompactFilterMenu: Bool = false {
        didSet {
            updateFilterTitle()
        }
    }
    var groupFilterChanged: ((Int) -> Void)?
    private var groupFilterTitles: [String] = []
    private var groupFilterEnabledStates: [Bool] = []
    private var groupFilterSelectedIndex: Int = 0
    private var usesGroupFilterLayout: Bool = false
    
    /// 选中的设备
    private(set) var selectDevice: Node?
    var isSequence: Bool = true
    
    private(set) var devices: [Node] = []

    var preferredContentHeight: CGFloat {
        if !guideContentView.isHidden {
            return SCRYFrom(68)
        }
        let collectionHeight = max(currentCollectionHeight(), preferredMinimumCollectionHeight)
        return topContentInset + SCRYFrom(30 + 16 + 38) + collectionHeight
    }

    var preferredMinimumContentHeight: CGFloat {
        topContentInset + SCRYFrom(30 + 16 + 38) + preferredMinimumCollectionHeight
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.snp.updateConstraints { make in
            make.height.equalTo(currentCollectionHeight())
        }
    }
    
    func reloadData(devices: [Node], selectDevice: Node?) {
        self.devices = devices
        self.selectDevice = selectDevice
        
        noDevicesLabel.isHidden = devices.count > 0
        collectionView.reloadData()
        pageControl.numberOfPages = Int(ceilf(Float(devices.count) / Float(colNum * rowNum)))
    }

    func setGuideVisible(_ visible: Bool) {
        guideContentView.isHidden = !visible
        helpImageView.isHidden = visible
        addTypeView.isHidden = visible
        groupFilterView.isHidden = visible || !usesGroupFilterLayout
        collectionView.isHidden = visible
        pageControl.isHidden = visible
        noDevicesLabel.isHidden = visible || devices.count > 0
    }
    
    @objc private func addTypeSelectAction() {
        let menuWidth = usesCompactFilterMenu ? (isIPad ? SCRXFrom(320) : SCRXFrom(256)) : (isIPad ? SCRXFrom(300) : SCRXFrom(256))
        let titles = menuTitles()
        let btnPoint = CGPoint(x: addTypeView.frame.maxX - menuWidth, y: addTypeView.frame.maxY + SCRYFrom(4))
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())

//        if usesCompactFilterMenu {
            TitleSelectView.show(titles: titles,
                                 style: .default,
                                 anchorPoint: windowPoint,
                                 selectIndex: showAdded ? 1 : 0,
                                 menuWidth: menuWidth,
                                 itemHeight: SCRYFrom(30),
                                 titleColor: RGB(100, 116, 139),
                                 titleFont: UIFont.systemFont(ofSize: 12, weight: .regular),
                                 backgroundColor: .white,
                                 selectBackgroundColor: Bar_Color.withAlphaComponent(0.12),
                                 selectedTitleColor: Bar_Color,
                                 highlightSelectedWithoutIcon: true,
                                 titleAlignment: .left,
                                 contentBorderColor: RGB(236, 236, 236),
                                 contentBorderWidth: 1,
                                 contentCornerRadius: SCRYFrom(10),
                                 rowHighlightInsets: UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(4), bottom: SCRYFrom(4), right: SCRXFrom(4)),
                                 rowHighlightCornerRadius: SCRYFrom(5)) {[weak self] index in
                guard let self = self else { return }
                self.showAdded = index == 1
                self.updateFilterTitle()
                self.delegate?.manuallyAddView(self, showAddedDevicesChanged: self.showAdded)
            }
//            return
//        }
//
//        TitleSelectView.show(titles: titles, style: .default, anchorPoint: windowPoint, menuWidth: menuWidth, itemHeight: SCRYFrom(44), titleFont: UIFont.systemFont(ofSize: 14, weight: .light)) {[weak self] index in
//            guard let self = self else { return }
//            self.showAdded = index == 1
//            self.updateFilterTitle()
//            self.delegate?.manuallyAddView(self, showAddedDevicesChanged: self.showAdded)
//        }
        
    }

    @objc private func groupFilterSelectAction() {
        guard usesGroupFilterLayout, !groupFilterTitles.isEmpty else {
            return
        }
        let menuWidth = groupFilterView.bounds.width > 0 ? groupFilterView.bounds.width : SCRXFrom(186)
        let btnPoint = CGPoint(x: groupFilterView.frame.maxX - menuWidth, y: groupFilterView.frame.maxY + SCRYFrom(4))
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())

        TitleSelectView.show(titles: groupFilterTitles,
                             style: .default,
                             anchorPoint: windowPoint,
                             selectIndex: groupFilterSelectedIndex,
                             menuWidth: menuWidth,
                             itemHeight: SCRYFrom(30),
                             titleColor: RGB(100, 116, 139),
                             titleFont: UIFont.systemFont(ofSize: 12, weight: .regular),
                             backgroundColor: .white,
                             selectBackgroundColor: Bar_Color.withAlphaComponent(0.12),
                             enabledStates: groupFilterEnabledStates,
                             disabledTitleColor: RGB(100, 116, 139, 0.5),
                             selectedTitleColor: Bar_Color,
                             highlightSelectedWithoutIcon: true,
                             titleAlignment: .left,
                             contentBorderColor: RGB(236, 236, 236),
                             contentBorderWidth: 1,
                             contentCornerRadius: SCRYFrom(10),
                             rowHighlightInsets: UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(4), bottom: SCRYFrom(4), right: SCRXFrom(4)),
                             rowHighlightCornerRadius: SCRYFrom(5)) { [weak self] index in
            guard let self else { return }
            self.groupFilterSelectedIndex = index
            self.groupTitleLabel.text = self.groupFilterTitles[index]
            self.groupFilterChanged?(index)
        }
    }

    private func menuTitles() -> [String] {
        if usesCompactFilterMenu {
            return ["quick_add_ignore_added_devices".localizedString, "trigger_add_show_added_devices".localizedString]
        }
        if !isSequence {
            return [
                "trigger_add_hide_added_devices".localizedString,
                "zone_trigger_add_show_added_devices".localizedString
            ]
        }
        return ["trigger_add_hide_added_devices".localizedString, "trigger_add_show_added_devices".localizedString]
    }

    private func updateFilterTitle() {
        if usesCompactFilterMenu {
            titleLabel.text = showAdded ? "space_trigger_zone_used".localizedString : "space_trigger_zone_new_only".localizedString
            return
        }
        titleLabel.text = showAdded ? menuTitles()[1] : menuTitles()[0]
    }

    func configureDefaultFilterLayout() {
        usesGroupFilterLayout = false
        groupFilterTitles.removeAll()
        groupFilterEnabledStates.removeAll()
        groupFilterSelectedIndex = 0
        groupFilterView.isHidden = true
        addTypeView.snp.remakeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(topContentInset)
            make.height.equalTo(SCRYFrom(30))
        }
    }

    func configureSpaceTriggerZoneFilterLayout(groupTitles: [String], enabledStates: [Bool], selectedGroupIndex: Int, showAddedOnly: Bool) {
        usesGroupFilterLayout = true
        groupFilterTitles = groupTitles
        groupFilterEnabledStates = enabledStates
        groupFilterSelectedIndex = max(0, min(selectedGroupIndex, max(groupTitles.count - 1, 0)))
        groupTitleLabel.text = groupFilterTitles.isEmpty ? nil : groupFilterTitles[groupFilterSelectedIndex]
        showAdded = showAddedOnly
        groupFilterView.isHidden = false
        updateFilterTitle()
        addTypeView.snp.remakeConstraints { make in
            make.left.equalTo(groupFilterView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(topContentInset)
            make.height.equalTo(SCRYFrom(30))
            make.width.equalTo(SCRXFrom(90))
            make.right.lessThanOrEqualTo(SCRXFrom(-16))
        }
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }

    private func currentCollectionHeight() -> CGFloat {
        guard collectionView.frame != .zero else {
            return preferredMinimumCollectionHeight
        }

        var itemWidth = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat(colNum - 1)) / CGFloat(colNum)
        itemWidth = CGFloat(floorf(Float(itemWidth) * 100) / 100.0)
        return itemWidth * CGFloat(rowNum) + CGFloat(rowNum - 1) * flowLayout.minimumLineSpacing
    }

    private var preferredMinimumCollectionHeight: CGFloat {
        isIPad ? SCRYFrom(64) : SCRYFrom(44)
    }
    
    private func setupUI() {
        helpImageView = UIImageView(image: UIImage(named: "help"))
        addSubview(helpImageView)
        helpImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(topContentInset)
            make.width.height.equalTo(30)
        }

        groupFilterView = UIView()
        groupFilterView.isHidden = true
        groupFilterView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(groupFilterSelectAction)))
        groupFilterView.layer.cornerRadius = SCRYFrom(10)
        groupFilterView.layer.borderWidth = 1
        groupFilterView.layer.borderColor = Border_Color.cgColor
        groupFilterView.backgroundColor = .white
        addSubview(groupFilterView)
        groupFilterView.snp.makeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(SCRXFrom(6))
            make.top.equalTo(topContentInset)
            make.height.equalTo(SCRYFrom(30))
            make.width.equalTo(SCRXFrom(186))
        }

        groupArrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        groupFilterView.addSubview(groupArrowImageView)
        groupArrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }

        groupTitleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 13, fontWeight: .light, fit: false)
        groupFilterView.addSubview(groupTitleLabel)
        groupTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.right.equalTo(groupArrowImageView.snp.left).offset(SCRXFrom(-8))
        }
        
        addTypeView = UIView()
        addTypeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addTypeSelectAction)))
        addTypeView.layer.cornerRadius = SCRYFrom(10)
        addTypeView.layer.borderWidth = 1
        addTypeView.layer.borderColor = Border_Color.cgColor
        addTypeView.backgroundColor = .white
        addSubview(addTypeView)
        addTypeView.snp.makeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(topContentInset)
            make.height.equalTo(SCRYFrom(30))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        addTypeView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 13, fontWeight: .light, fit: false)
        addTypeView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-12))
        }
        
        flowLayout = HorizontalDirectionFlowLayout()
        flowLayout.itemColCount = rowNum
        flowLayout.itemRowCount = colNum
        flowLayout.minimumInteritemSpacing = SCRXFrom(18)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(26), bottom: 0, right: SCRXFrom(25))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
//        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(26), bottom: 0, right: SCRXFrom(25))
        collectionView.isPagingEnabled = true
        collectionView.register(GroupPathSequenceAddDeviceCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(addTypeView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(preferredMinimumCollectionHeight)
            make.bottom.equalTo(SCRYFrom(-38))
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
        
        guideContentView = UIView()
        guideContentView.backgroundColor = .clear
        guideContentView.isHidden = true
        addSubview(guideContentView)
        guideContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        guideView = GroupPathSequenceDeviceAddStepView(frame: .zero, steps: [
            .init(imageName: "proximity_lighting_step1", title: "quick_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "path_manual_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_manual_add_step3".localizedString, textColor: SubText_Color)
        ])
        guideContentView.addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-12))
        }

        configureDefaultFilterLayout()
        setGuideVisible(false)
        updateFilterTitle()
    }
}

extension GroupPathSequenceManuallyAddView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
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
        if cell.interactions.isEmpty {
            cell.addInteraction(UIDragInteraction(delegate: self))
        }
        return cell
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        
//        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(colCount - 1)) / CGFloat(colCount)
//        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
//        return CGSize(width: itemW, height: itemW)
//    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let device = devices[indexPath.item]
        if device == selectDevice {
            delegate?.manuallyAddView(self, selectDevice: device)
        }else {
            selectDevice = device
            delegate?.manuallyAddView(self, identifyDevice: device)
        }
        selectDevice = device
        collectionView.reloadData()
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
    }
    
}

extension GroupPathSequenceManuallyAddView: UIDragInteractionDelegate {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        
        guard let item = interaction.view as? GroupPathSequenceAddDeviceCell, let index = collectionView.indexPath(for: item)?.item else { return [] }
        let node = devices[index]
        let address = node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
        
        let itemProvider = NSItemProvider(object: address.hex as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = address
        return [dragItem]
    }
}
