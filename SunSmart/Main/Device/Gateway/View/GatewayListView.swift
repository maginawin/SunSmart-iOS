//
//  GatewayListView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/1/XX.
//

import UIKit
import SnapKit
import NordicSigMeshSDK

/// 网关状态
enum GatewayStatus {
    case online      // 在线（绿色）
    case offline     // 离线（灰色）
    case warning     // 警告（黄色）
}

/// 网关列表项数据模型
struct GatewayListItem {
    var id: String              // 标识符，Overview 为 "overview"，网关为 mac 地址
    var title: String           // 标题
    var status: GatewayStatus?  // 状态（Overview 为 nil）
    var isSelected: Bool        // 是否选中
    var gatewayModel: GatewayModel? // 网关模型（Overview 为 nil）
    
    init(id: String, title: String, status: GatewayStatus? = nil, isSelected: Bool = false, gatewayModel: GatewayModel? = nil) {
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
}

class GatewayListView: UIView {
    
    weak var delegate: GatewayListViewDelegate?
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var items: [GatewayListItem] = []
    private var itemViews: [GatewayItemView] = []
    private var separatorViews: [UIView] = []
    private var menuButton: UIButton!
    
    /// 当前选中的索引
    var selectedIndex: Int = 0 {
        didSet {
            updateSelectedState()
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
        
        scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.right.equalToSuperview().offset(SCRXFrom(-50))
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalTo(0)
//            make.width.greaterThanOrEqualTo(scrollView.snp.width)
        }
        
        menuButton = UIButton(type: .custom)
        // 使用系统图标创建三条横线菜单图标
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            menuButton.setImage(UIImage(systemName: "line.horizontal.3", withConfiguration: config), for: .normal)
        } else {
            // iOS 13 以下使用其他图标或自定义绘制
            menuButton.setImage(UIImage(named: "menu_select"), for: .normal)
        }
        menuButton.tintColor = ImportantText_Color
        menuButton.addTarget(self, action: #selector(menuButtonAction), for: .touchUpInside)
        addSubview(menuButton)
        menuButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(24))
        }
    }
    
    @objc private func menuButtonAction() {
        delegate?.gatewayListViewDidClickMenu(self)
    }
    
    /// 更新网关列表数据
    func updateItems(_ items: [GatewayListItem]) {
        self.items = items
        
        // 清除旧的视图
        itemViews.forEach { $0.removeFromSuperview() }
        separatorViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        separatorViews.removeAll()
        
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
            if index < items.count - 1 {
                let separator = UIView()
                separator.backgroundColor = Line_Color
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
        
        var currentX: CGFloat = SCRXFrom(16)
        let itemHeight = max(frame.height, SCRYFrom(44))
        
        for (index, itemView) in itemViews.enumerated() {
            let item = items[index]
            
            // 计算文字宽度
            let titleWidth = item.title.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: itemHeight),
                options: .usesLineFragmentOrigin,
                attributes: [.font: UIFont.systemFont(ofSize: SCRYFrom(14))],
                context: nil
            ).width
            
            // 如果有状态指示器，增加宽度
            let statusDotWidth: CGFloat = item.status != nil ? SCRXFrom(8) + SCRXFrom(6) : 0
            let itemPadding: CGFloat = SCRXFrom(16)
            let itemWidth = max(SCRXFrom(80), titleWidth + statusDotWidth + itemPadding * 2)
            
            itemView.frame = CGRect(x: currentX, y: 0, width: itemWidth, height: itemHeight)
            currentX += itemWidth
            
            // 添加分隔线
            if index < separatorViews.count {
                let separator = separatorViews[index]
                let separatorHeight = itemHeight - SCRYFrom(16)
                separator.frame = CGRect(x: currentX, y: SCRYFrom(8), width: 0.5, height: separatorHeight)
                currentX += SCRXFrom(1)
            }
        }
        
        let totalWidth = currentX + SCRXFrom(16)
        
        // 更新 contentView 的宽度
        contentView.snp.updateConstraints { make in
            make.width.equalTo(totalWidth)
        }
        
        scrollView.contentSize = CGSize(width: totalWidth, height: itemHeight)
    }
}

/// 网关列表项视图
class GatewayItemView: UIView {
    
    private var statusDot: UIView!
    private var titleLabel: UILabel!
    private var underlineView: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        statusDot = UIView()
        statusDot.layer.cornerRadius = SCRXFrom(4)
        statusDot.isHidden = true
        addSubview(statusDot)
        statusDot.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(8))
        }
        
        titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14))
        titleLabel.textColor = ImportantText_Color
        titleLabel.textAlignment = .left
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(statusDot.snp.right).offset(SCRXFrom(6))
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        
        underlineView = UIView()
        underlineView.backgroundColor = Bar_Color
        underlineView.isHidden = true
        addSubview(underlineView)
        underlineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(2))
        }
    }
    
    func update(with item: GatewayListItem) {
        titleLabel.text = item.title
        
        // 更新状态指示器
        if let status = item.status {
            statusDot.isHidden = false
            switch status {
            case .online:
                statusDot.backgroundColor = Green_Color
            case .offline:
                statusDot.backgroundColor = RGB(156, 163, 175) // 灰色
            case .warning:
                statusDot.backgroundColor = Yellow_Color
            }
            // 有状态指示器时，标题在状态指示器右侧
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(statusDot.snp.right).offset(SCRXFrom(6))
                make.right.equalToSuperview()
                make.centerY.equalToSuperview()
            }
        } else {
            statusDot.isHidden = true
            // 无状态指示器时，标题靠左对齐
            titleLabel.snp.remakeConstraints { make in
                make.left.equalToSuperview()
                make.right.equalToSuperview()
                make.centerY.equalToSuperview()
            }
        }
        
        // 更新选中状态
        underlineView.isHidden = !item.isSelected
        // 文字颜色统一使用 ImportantText_Color，选中状态通过下划线显示
        titleLabel.textColor = ImportantText_Color
    }
}

