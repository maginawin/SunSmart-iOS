//
//  GatewayListView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/1/XX.
//

import UIKit
import SnapKit
import NordicSigMeshSDK


/// 网关列表项数据模型
struct GatewayListItem {
    var id: String              // 标识符，Overview 为 "overview"，网关为 mac 地址
    var title: String           // 标题
    var status: GatewayConnectStatus?  // 状态（Overview 为 nil）
    var isSelected: Bool        // 是否选中
    var gatewayModel: GatewayModel? // 网关模型（Overview 为 nil）
    
    init(id: String, title: String, status: GatewayConnectStatus? = nil, isSelected: Bool = false, gatewayModel: GatewayModel? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.isSelected = isSelected
        self.gatewayModel = gatewayModel
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
    private var itemViews: [GatewayItemView] = []
    private var separatorViews: [UIView] = []
    private var menuButton: UIButton!
    
    private var addGatewyaBtn: UIButton!
    
    /// 当前选中的索引
    var selectedIndex: Int = 0 {
        didSet {
            updateSelectedState()
            // 当 selectedIndex 改变时，自动滚动到选中位置
            if selectedIndex != oldValue {
                scrollToItem(at: selectedIndex, animated: true)
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
//        scrollView.alwaysBounceHorizontal = true
//        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.right.equalTo(0)
//            make.right.equalTo(menuButton.snp.left)
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
        
        // 清除旧的视图
        itemViews.forEach { $0.removeFromSuperview() }
        separatorViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        separatorViews.removeAll()
        
        menuButton.isHidden = items.isEmpty
        addGatewyaBtn.isHidden = items.count > 0
        
        // 创建新的视图
        for (index, item) in items.enumerated() {
            let itemView = GatewayItemView()
            var itemWithSelection = item
            itemWithSelection.isSelected = (index == selectedIndex)
            itemView.update(with: itemWithSelection)
            itemView.isUserInteractionEnabled = true
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(itemViewTapped(_:)))
            itemView.addGestureRecognizer(tapGesture)
            contentView.addSubview(itemView)
            itemViews.append(itemView)
            
            // 添加分隔线（项与项之间需要分隔线）
            if index < items.count {
                let separator = UIView()
                separator.backgroundColor = Line_Color1
                contentView.addSubview(separator)
                separatorViews.append(separator)
            }
        }
        
        // 强制布局更新
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    @objc private func itemViewTapped(_ gesture: UITapGestureRecognizer) {
        guard let itemView = gesture.view as? GatewayItemView,
              let index = itemViews.firstIndex(of: itemView),
              index < items.count else {
            return
        }
        
        guard index != selectedIndex else {
            return
        }
        
        selectedIndex = index
        delegate?.gatewayListView(self, didSelectItem: items[index], at: index)
        // 注意：滚动逻辑在 selectedIndex 的 didSet 中处理
    }
    
    /// 滚动到指定索引的 item
    /// - Parameters:
    ///   - index: item 索引
    ///   - animated: 是否使用动画
    private func scrollToItem(at index: Int, animated: Bool) {
        guard index >= 0 && index < itemViews.count else {
            return
        }
        
        // 确保布局已更新
        layoutIfNeeded()
        
        let itemView = itemViews[index]
        let itemFrame = itemView.frame
        
        // 计算 item 的中心位置
        let itemCenterX = itemFrame.midX
        
        // 计算 scrollView 的可视区域宽度
        let visibleWidth = scrollView.bounds.width
        
        // 计算目标偏移量（让 item 居中显示）
        var targetOffsetX = itemCenterX - visibleWidth / 2
        
        // 限制在有效范围内
        let maxOffsetX = max(0, scrollView.contentSize.width - visibleWidth)
        targetOffsetX = max(0, min(targetOffsetX, maxOffsetX))
        
        // 如果 item 已经在可见区域内，且不需要居中，可以只滚动到可见区域
//        let currentOffsetX = scrollView.contentOffset.x
//        let currentVisibleRight = currentOffsetX + visibleWidth
        
        // 如果 item 完全在可见区域内，仍然居中显示（提供更好的用户体验）
        // 如果需要只在 item 不在可见区域时才滚动，可以取消下面的注释
        /*
        if itemFrame.minX >= currentOffsetX && itemFrame.maxX <= currentVisibleRight {
            return
        }
        */
        
        // 执行滚动
        scrollView.setContentOffset(CGPoint(x: targetOffsetX, y: 0), animated: animated)
    }
    
    private func updateSelectedState() {
        for (index, itemView) in itemViews.enumerated() {
            var item = items[index]
            item.isSelected = (index == selectedIndex)
            itemView.update(with: item)
        }
    }
    
    private func updateLayout() {
        guard !itemViews.isEmpty, !frame.isEmpty else { return }
        
        var currentX: CGFloat = 0// SCRXFrom(16)
        let itemHeight = SCRYFrom(40)
        
        for (index, itemView) in itemViews.enumerated() {
            let item = items[index]
            
            // 计算文字宽度
            let titleWidth = item.title.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: itemHeight),
                options: .usesLineFragmentOrigin,
                attributes: [.font: UIFont.systemFont(ofSize: FontFit(12), weight: .light)],
                context: nil
            ).width
            
            
            // 如果有状态指示器，增加宽度
            let statusDotWidth: CGFloat = item.status != nil ? SCRXFrom(8) + SCRXFrom(6) : 0
            let failImageWidth = item.gatewayModel?.syncCloudError != nil ? 12 + SCRXFrom(6) : 0
            let itemPadding: CGFloat = SCRXFrom(10) //SCRXFrom(16)
            let itemWidth = max(SCRXFrom(76), titleWidth + statusDotWidth + failImageWidth + itemPadding * 2)
            
            itemView.frame = CGRect(x: currentX, y: 0, width: itemWidth, height: itemHeight)
            currentX += itemWidth
            
            // 添加分隔线
            if index < separatorViews.count {
                let separator = separatorViews[index]
                let separatorHeight = itemHeight - SCRYFrom(16)
                separator.frame = CGRect(x: currentX, y: SCRYFrom(8), width: 0.5, height: separatorHeight)
                currentX += SCRXFrom(4)
            }
        }
        
        
        scrollView.snp.updateConstraints { make in
            make.right.equalTo(-40)
        }
        
        let totalWidth = currentX// + SCRXFrom(16)
        
        // 更新 contentView 的宽度
        contentView.snp.updateConstraints { make in
            make.width.equalTo(totalWidth)
        }
        
        scrollView.contentSize = CGSize(width: totalWidth, height: itemHeight)
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
        titleLabel.textColor = item.isSelected ? Bar_Color : ImportantText_Color
        contentView.subviews.forEach({ $0.removeFromSuperview() })
        
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

