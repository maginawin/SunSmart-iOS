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

/// Limit gesture coordination to this Site header, leaving other paged screens unchanged.
private final class GatewayHorizontalScrollView: UIScrollView, UIGestureRecognizerDelegate {
    weak var pagingPanGesture: UIGestureRecognizer?
    weak var navigationBackGesture: UIGestureRecognizer?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            return contentSize.width > bounds.width && abs(velocity.x) > abs(velocity.y)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === panGestureRecognizer && otherGestureRecognizer === pagingPanGesture
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === panGestureRecognizer && otherGestureRecognizer === navigationBackGesture
    }
}

class GatewayListView: UIView, UIScrollViewDelegate {

    weak var delegate: GatewayListViewDelegate?

    private let scrollView = GatewayHorizontalScrollView()
    private let contentView = UIView()
    private let menuSeparator = UIView()
    private var items: [GatewayListItem] = []
    private var gatewayIDs: [String] = []
    private var itemViews: [GatewayItemView] = []
    private var separatorViews: [UIView] = []
    private var menuButton: UIButton!
    private var addGatewyaBtn: UIButton!
    private let menuAreaWidth = SCRXFrom(40)
    private var scrollState = SiteGatewayListScrollState()
    private var currentLayout: SiteGatewayListLayout?
    private var needsScrollRestore = false
    private var isUpdatingLayout = false

    private(set) var selectedIndex = 0

    var isMenuButtonVisible: Bool = true {
        didSet {
            menuButton.isHidden = !isMenuButtonVisible || items.isEmpty
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

    func coordinateScrolling(with pagingScrollView: UIScrollView, navigationBackGesture: UIGestureRecognizer?) {
        scrollView.pagingPanGesture = pagingScrollView.panGestureRecognizer
        scrollView.navigationBackGesture = navigationBackGesture
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)

        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        menuButton = UIButton(normalImageName: "gateway_more", target: self, action: #selector(menuButtonAction))
        addSubview(menuButton)
        menuButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.equalTo(menuAreaWidth)
            make.height.equalTo(40)
        }
        menuSeparator.backgroundColor = RGB(220, 220, 220)
        addSubview(menuSeparator)

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

    /// Supply data and selection together so header reuse never reveals a stale index.
    /// Status-only refreshes may omit selection and retain it by ID.
    func updateItems(
        _ items: [GatewayListItem],
        selectedIndex: Int? = nil,
        scrollState: SiteGatewayListScrollState? = nil
    ) {
        let stateChanged = scrollState.map { $0 !== self.scrollState } ?? false
        if let scrollState {
            self.scrollState = scrollState
        }
        let idsChanged = self.items.map(\.id) != items.map(\.id)
        let resolvedIndex = selectedIndex ?? items.firstIndex { $0.id == self.scrollState.selectedItemID } ?? 0
        self.selectedIndex = items.indices.contains(resolvedIndex) ? resolvedIndex : 0
        let selectedID = items.isEmpty ? nil : items[self.selectedIndex].id
        self.scrollState.selectItem(selectedID)
        needsScrollRestore = needsScrollRestore || stateChanged || idsChanged
        self.items = items
        gatewayIDs = items.dropFirst().map(\.id)
        menuButton.isHidden = !isMenuButtonVisible || items.isEmpty
        menuSeparator.isHidden = items.isEmpty
        scrollView.isHidden = items.isEmpty
        addGatewyaBtn.isHidden = !items.isEmpty
        if idsChanged {
            rebuildItemViews()
        }
        updateSelectedState()
        setNeedsLayout()
        layoutIfNeeded()
    }

    @objc private func itemViewTapped(_ gesture: UITapGestureRecognizer) {
        guard let itemView = gesture.view as? GatewayItemView,
              let index = itemViews.firstIndex(of: itemView) else {
            return
        }
        let selectionChanged = index != selectedIndex
        selectedIndex = index
        scrollState.selectItem(items[index].id, reveal: true)
        updateSelectedState()
        setNeedsLayout()
        layoutIfNeeded()
        if selectionChanged {
            delegate?.gatewayListView(self, didSelectItem: items[index], at: index)
        }
    }

    private func updateSelectedState() {
        for (index, itemView) in itemViews.enumerated() {
            var item = items[index]
            item.isSelected = index == selectedIndex
            itemView.update(with: item)
        }
    }

    private func updateLayout() {
        let availableWidth = max(0, bounds.width - menuAreaWidth)
        guard availableWidth > 0, bounds.height > 0 else { return }
        isUpdatingLayout = true
        let layout = SiteGatewayListLayout(availableWidth: availableWidth, gatewayCount: gatewayIDs.count)
        let sizeChanged = scrollState.availableWidth.map { $0 != availableWidth } ?? false
        let itemHeight = bounds.height
        let separatorHeight = max(0, itemHeight - SCRYFrom(16))
        scrollView.frame = CGRect(x: layout.itemWidth, y: 0, width: layout.viewportWidth, height: itemHeight)
        contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: itemHeight)
        scrollView.contentSize = contentView.bounds.size
        scrollView.showsHorizontalScrollIndicator = false 
        menuSeparator.frame = CGRect(x: availableWidth - 0.5, y: SCRYFrom(8), width: 1, height: separatorHeight)

        for (index, itemView) in itemViews.enumerated() {
            let x = index == 0 ? 0 : CGFloat(index - 1) * layout.itemWidth
            itemView.frame = CGRect(x: x, y: 0, width: layout.itemWidth, height: itemHeight)
            separatorViews[index].frame = CGRect(x: x + layout.itemWidth - 0.5, y: SCRYFrom(8), width: 1, height: separatorHeight)
        }

        var offset = layout.clampedOffset(scrollView.contentOffset.x)
        if needsScrollRestore || sizeChanged, let position = scrollState.position {
            offset = position.restoredOffset(gatewayIDs: gatewayIDs, layout: layout)
        }
        if (scrollState.needsSelectionReveal || sizeChanged), selectedIndex > 0 {
            offset = layout.offsetToReveal(gatewayIndex: selectedIndex - 1, currentOffset: offset)
        }
        scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
        currentLayout = layout
        scrollState.availableWidth = availableWidth
        needsScrollRestore = false
        scrollState.needsSelectionReveal = false
        isUpdatingLayout = false
        saveScrollPosition()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingLayout, !needsScrollRestore else { return }
        saveScrollPosition()
    }

    private func saveScrollPosition() {
        guard let currentLayout else { return }
        scrollState.position = SiteGatewayListScrollPosition(
            gatewayIDs: gatewayIDs,
            offset: scrollView.contentOffset.x,
            layout: currentLayout
        )
    }

    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        separatorViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        separatorViews.removeAll()
        for index in items.indices {
            let itemView = GatewayItemView()
            itemView.isUserInteractionEnabled = true
            itemView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemViewTapped(_:))))
            let parent = index == 0 ? self : contentView
            parent.addSubview(itemView)
            itemViews.append(itemView)
            let separator = UIView()
            separator.backgroundColor = RGB(220, 220, 220)
            parent.addSubview(separator)
            separatorViews.append(separator)
        }
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
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().offset(-SCRXFrom(12))
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
        titleLabel.lineBreakMode = .byTruncatingMiddle
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
        syncFailImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
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
