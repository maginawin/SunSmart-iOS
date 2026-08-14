//
//  GatewayListView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/1/XX.
//

import UIKit
import SnapKit
import NordicSigMeshSDK

enum SiteGatewayTimeZoneSyncAppearance {
    static let pendingNameColor = RGB(187, 77, 0)
    static let menuPendingNameColor = RGB(255, 210, 48)
}

/// 网关列表项数据模型
struct GatewayListItem {
    var id: String              // 标识符，Overview 为 "overview"，网关为 mac 地址
    var title: String           // 标题
    var status: GatewayConnectStatus?  // 状态（Overview 为 nil）
    var isSelected: Bool        // 是否选中
    var gatewayModel: GatewayModel? // 网关模型（Overview 为 nil）
    var needsTimeZoneSync: Bool
    
    init(
        id: String,
        title: String,
        status: GatewayConnectStatus? = nil,
        isSelected: Bool = false,
        gatewayModel: GatewayModel? = nil,
        needsTimeZoneSync: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.isSelected = isSelected
        self.gatewayModel = gatewayModel
        self.needsTimeZoneSync = needsTimeZoneSync
    }
}

protocol GatewayListViewDelegate: AnyObject {
    /// 点击网关项回调
    func gatewayListView(_ view: GatewayListView, didSelectItem item: GatewayListItem, at index: Int)
    
    /// 点击菜单按钮回调
    func gatewayListViewDidClickMenu(_ view: GatewayListView)
    
    /// 点击菜单按钮回调
    func gatewayListViewDidClickAdd(_ view: GatewayListView)
}

class GatewayListView: UIView {
    
    weak var delegate: GatewayListViewDelegate?
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var items: [GatewayListItem] = []
    private var visibleItemIndexes: [Int] = []
    private var itemViews: [GatewayItemView] = []
    private var separatorViews: [UIView] = []
    private var menuButton: UIButton!
    
    private var addGatewyaBtn: UIButton!
    private let menuAreaWidth = SCRXFrom(40)
    private let maxVisibleItemCount = 4
    
    /// 当前选中的索引
    var selectedIndex: Int = 0 {
        didSet {
            guard !items.isEmpty else {
                return
            }
            if calculateVisibleItemIndexes() != visibleItemIndexes {
                rebuildItemViews()
            } else {
                updateSelectedState()
                setNeedsLayout()
            }
        }
    }
    
    /// 菜单按钮是否显示
    var isMenuButtonVisible: Bool = true {
        didSet {
            menuButton.isHidden = !isMenuButtonVisible
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }
    
    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        menuButton = UIButton(normalImageName: "gateway_more", target: self, action: #selector(menuButtonAction))
        addSubview(menuButton)
        menuButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(40)
        }
        
        scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.isScrollEnabled = false
        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.right.equalTo(-menuAreaWidth)
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalTo(0)
        }
        
        addGatewyaBtn = UIButton(title: "click_add_gateway".localizedString, titleSize: 14, titleWeight: .light, titleColor: ImportantText_Color, normalImageName: "gateway_add", target: self, action: #selector(addGatewyaBtnAction))
        addGatewyaBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addGatewyaBtn.layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        addGatewyaBtn.layer.shadowOpacity = 1
        addGatewyaBtn.layer.shadowOffset = CGSize(width: -4, height: 0)
        addGatewyaBtn.isHidden = true
        addSubview(addGatewyaBtn)
        addGatewyaBtn.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    @objc private func menuButtonAction() {
        delegate?.gatewayListViewDidClickMenu(self)
    }
    
    @objc private func addGatewyaBtnAction() {
        delegate?.gatewayListViewDidClickAdd(self)
    }
    
    /// 更新网关列表数据
    func updateItems(_ items: [GatewayListItem]) {
        self.items = items
        if !items.indices.contains(selectedIndex) {
            selectedIndex = 0
        }
        menuButton.isHidden = items.isEmpty
        addGatewyaBtn.isHidden = items.count > 0
        rebuildItemViews()
    }
    
    @objc private func itemViewTapped(_ gesture: UITapGestureRecognizer) {
        guard let itemView = gesture.view as? GatewayItemView,
              let index = itemViews.firstIndex(of: itemView),
              index < visibleItemIndexes.count else {
            return
        }
        let itemIndex = visibleItemIndexes[index]
        
        guard itemIndex != selectedIndex else {
            return
        }
        
        selectedIndex = itemIndex
        delegate?.gatewayListView(self, didSelectItem: items[itemIndex], at: itemIndex)
    }
    
    private func updateSelectedState() {
        for (index, itemView) in itemViews.enumerated() {
            let itemIndex = visibleItemIndexes[index]
            var item = items[itemIndex]
            item.isSelected = (itemIndex == selectedIndex)
            itemView.update(with: item)
        }
    }
    
    private func updateLayout() {
        guard !itemViews.isEmpty, !frame.isEmpty else { return }
        
        let itemHeight = SCRYFrom(40)
        let contentWidth = scrollView.bounds.width
        guard contentWidth > 0 else { return }
        let itemWidth = contentWidth / CGFloat(itemViews.count)
        
        for (index, itemView) in itemViews.enumerated() {
            itemView.frame = CGRect(x: itemWidth * CGFloat(index), y: 0, width: itemWidth, height: itemHeight)
        }
        
        let separatorHeight = itemHeight - SCRYFrom(16)
        for (index, separator) in separatorViews.enumerated() {
            let separatorX = index == separatorViews.count - 1 ? (contentWidth - 0.5) : (itemWidth * CGFloat(index + 1) - 0.5)
            separator.frame = CGRect(x: separatorX, y: SCRYFrom(8), width: 1, height: separatorHeight)
        }
        
        contentView.snp.updateConstraints { make in
            make.width.equalTo(contentWidth)
        }
        
        scrollView.contentSize = CGSize(width: contentWidth, height: itemHeight)
    }
    
    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        separatorViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        separatorViews.removeAll()
        visibleItemIndexes = calculateVisibleItemIndexes()
        
        for itemIndex in visibleItemIndexes {
            let itemView = GatewayItemView()
            var itemWithSelection = items[itemIndex]
            itemWithSelection.isSelected = (itemIndex == selectedIndex)
            itemView.update(with: itemWithSelection)
            itemView.isUserInteractionEnabled = true
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(itemViewTapped(_:)))
            itemView.addGestureRecognizer(tapGesture)
            contentView.addSubview(itemView)
            itemViews.append(itemView)
        }
        
        for _ in 0..<visibleItemIndexes.count {
            let separator = UIView()
            separator.backgroundColor = RGB(220, 220, 220)
            contentView.addSubview(separator)
            separatorViews.append(separator)
        }
        
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func calculateVisibleItemIndexes() -> [Int] {
        guard !items.isEmpty else {
            return []
        }
        if items.count <= maxVisibleItemCount {
            return Array(items.indices)
        }
        if selectedIndex < maxVisibleItemCount {
            return Array(0..<maxVisibleItemCount)
        }
        return [0, 1, 2, selectedIndex]
    }
}

/// 网关列表项视图
class GatewayItemView: UIView {
    
    private var contentView: UIStackView!
    private var statusDot: UIView!
    private var titleLabel: UILabel!
    private var syncFailImageView: UIImageView!
    private var underlineView: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        contentView = UIStackView()
        contentView.axis = .horizontal
        contentView.spacing = SCRXFrom(6)
        contentView.alignment = .center
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
//            make.width.lessThanOrEqualToSuperview()
        }
        
        statusDot = UIView()
        statusDot.layer.cornerRadius = SCRXFrom(3)
        statusDot.isHidden = true
//        addSubview(statusDot)
//        contentView.addArrangedSubview(statusDot)
//        statusDot.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(8))
//            make.centerY.equalToSuperview()
//            make.width.height.equalTo(SCRXFrom(8))
//        }
        
        titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        titleLabel.textColor = ImportantText_Color
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
//        titleLabel.textAlignment = .center
//        addSubview(titleLabel)
//        contentView.addArrangedSubview(titleLabel)
//        titleLabel.snp.makeConstraints { make in
//            make.left.equalTo(statusDot.snp.right).offset(SCRXFrom(6))
//            make.right.equalToSuperview()
//            make.centerY.equalToSuperview()
//        }
        
        syncFailImageView = UIImageView(image: UIImage(named: "gateway_sync_fail"))
        syncFailImageView.isHidden = true
        
        underlineView = UIView()
        underlineView.backgroundColor = Bar_Color
        underlineView.isHidden = true
        addSubview(underlineView)
        underlineView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(20))
            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(2))
        }
    }
    
    func update(with item: GatewayListItem) {
        titleLabel.text = item.title
        titleLabel.textColor = item.needsTimeZoneSync
            ? SiteGatewayTimeZoneSyncAppearance.pendingNameColor
            : (item.isSelected ? Bar_Color : ImportantText_Color)
        contentView.arrangedSubviews.forEach({ arrangedSubview in
            contentView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        })
        syncFailImageView.isHidden = true
        
        // 更新状态指示器
        if let status = item.status {
            statusDot.isHidden = false
            switch status {
            case .online:
                statusDot.backgroundColor = Green_Color
            case .offline, .reset:
                statusDot.backgroundColor = RGB(156, 163, 175) // 灰色
            case .inactive:
                statusDot.backgroundColor = Yellow_Color
            }
            titleLabel.textAlignment = .left
            titleLabel.font = UIFont.systemFont(ofSize: FontFit(12), weight: .light)
            contentView.addArrangedSubview(statusDot)
            statusDot.snp.makeConstraints { make in
                make.width.height.equalTo(SCRXFrom(6))
            }
            
        } else {
            titleLabel.textAlignment = .center
            statusDot.isHidden = true
            titleLabel.font = UIFont.systemFont(ofSize: FontFit(12))
        }
        
        contentView.addArrangedSubview(titleLabel)
        
        if item.gatewayModel?.syncCloudError != nil {
            syncFailImageView.isHidden = false
            contentView.addArrangedSubview(syncFailImageView)
        }
        
        // 更新选中状态
        underlineView.isHidden = !item.isSelected
    }
}
