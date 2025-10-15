//
//  ShareAuthorityFilterView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/31.
//

import UIKit

class ShareAuthorityFilterView: UIView {

    typealias FilterSelectCallback = ((FilterType?)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var tableView: UITableView!
    private var lineView: UIView!
    private var resetBtn: UIButton!
    /// 筛选项
    private var filters: [FilterData] = []
    
    /// 选中的筛选条件
    var selectFilter: FilterData?
    
    var selectCallback: FilterSelectCallback?
    
    
    /// 初始化
    /// - Parameters:
    ///   - selectFilterType: 选中的筛选项
    ///   - editorNames: 管理员名称list
    ///   - visitorNames: 访客名称list
    ///   - selectCallback: 筛选回调
    init(filters: [FilterData], selectFilterType: FilterType? = nil, selectCallback: FilterSelectCallback?) {
        
        super.init(frame: UIScreen.main.bounds)
        
        self.selectCallback = selectCallback
        self.filters = filters
        // 选中之前选中的筛选项
        if let type = selectFilterType {
            switch type {
            case .editorName(_), .visitorName(_):
                self.filters.enumerated().forEach { (sectionIndex, filter) in
                    if case .section(let items) = filter.options {
                        if let item = items.first(where: { $0.filterType! == type }) { 
                            filter.spread = true
                            self.selectFilter = item
                            items.enumerated().forEach { (index, item) in
                                self.filters.insert(item, at: sectionIndex + index + 1)
                            }
                        }
                    }
                }
            default:
                self.selectFilter = self.filters.first(where: { $0.filterType?.rawValue == type.rawValue })
            }
        }
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
            self.layoutIfNeeded()
            contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(20), height: SCRYFrom(20)))
        }
        contentView.y = self.height
        
        self.shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
        } completion: { _ in
            
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.2) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func close() {
        hide()
    }
    
    @objc private func reset() {
        selectCallback?(nil)
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
//        contentView.layer.cornerRadius = SCRYFrom(20)
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.snp.bottom)
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(480))
        }
        
        titleLabel = UILabel(text: "filter".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        resetBtn = UIButton(title: "Reset".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(reset))
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-kSafeAreaBottomHeight)
            make.height.equalTo(SCRYFrom(56))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(0, 0, 0, 0.03)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
            make.bottom.equalTo(resetBtn.snp.top)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(32)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
//        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(13))
            make.bottom.equalTo(lineView.snp.top)
        }
        
    }
    
}

extension ShareAuthorityFilterView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filters.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let filter = filters[indexPath.row]
        cell.cellStyle = .icon
        if let imageName = filter.icon {
            cell.iconImageView.image = UIImage(named: imageName)
        }else {
            cell.iconImageView.image = nil
        }
        cell.iconX = SCRXFrom(2)
        cell.titleX = SCRXFrom(40)
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.titleLabel.text = filter.name
        if let filterType = filter.filterType, let selectFilterType = selectFilter?.filterType {
            cell.titleLabel.textColor = filterType == selectFilterType ? Bar_Color : TextBlack_Color
        }else {
            cell.titleLabel.textColor = TextBlack_Color
        }
        if case .section = filter.options {
            cell.arrowImageView.isHidden = false
            cell.arrowImageView.image = UIImage(named: filter.spread ? "arrow_down_black" : "arrow_right_black")
        }else {
            cell.arrowImageView.isHidden = true
        }
        cell.selectionStyle = .gray
        cell.layer.cornerRadius = 8
        cell.clipsToBounds = true
        cell.lineView.isHidden = true
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let filter = filters[indexPath.row]
        
        switch filter.options {
        case .filter(let type):
            selectCallback?(type)
            hide()
        case .section(let items):
            // 是否展开
            if filter.spread {
                var indexPaths: [IndexPath] = []
                items.enumerated().forEach { (index, item) in
                    filters.remove(at: indexPath.item + 1)
                    indexPaths.append(IndexPath(row: indexPath.item + 1 + index, section: 0))
                }
                // 展开状态点击后收起，删除展开的数据
                tableView.deleteRows(at: indexPaths, with: .automatic)
            }else {
                // 收起状态点击后展开，显示展开的数据
                var indexPaths: [IndexPath] = []
                items.enumerated().forEach { (index, item) in
                    filters.insert(item, at: indexPath.item + index + 1)
                    indexPaths.append(IndexPath(row: indexPath.item + 1 + index, section: 0))
                }
                tableView.insertRows(at: indexPaths, with: .automatic)
            }
            filter.spread = !filter.spread
            
            if let cell = tableView.cellForRow(at: indexPath) as? CustomTableViewCell {
                cell.arrowImageView.image = UIImage(named: filter.spread ? "arrow_down_black" : "arrow_right_black")
            }
            
        }
        
    }
    
}

extension ShareAuthorityFilterView {
  
    class FilterData {
        
        enum Options {
            case filter(type: FilterType)
            case section(items: [FilterData])
        }

        let icon: String?
        let name: String
//        let type: FilterType
        let options: Options
        /// 是否展开（section类型）
        var spread: Bool = false
        /// 筛选条件
        var filterType: FilterType? {
            switch options {
            case .filter(let type):
                return type
            case .section:
                return nil
            }
        }
        
        init(icon: String?, name: String, options: Options) {
            self.icon = icon
            self.name = name
            self.options = options
        }
        
        /// 获取默认筛选数据
        static func defalutFilters(editorNames: [String], visitorNames: [String]) -> [FilterData] {
            
            let editorNameItems = editorNames.map({ FilterData(icon: nil, name: $0, options: .filter(type: .editorName(name: $0))) })
            let visitorNameItems = visitorNames.map({ FilterData(icon: nil, name: $0, options: .filter(type: .visitorName(name: $0))) })
            
            var filters: [FilterData] = []
//            filters.append(.init(icon: "filter_all", name: "all_space".localizedString, options: .filter(type: .none)))
            filters.append(.init(icon: "filter_favorite", name: "favorite_space".localizedString, options: .filter(type: .favorite)))
            filters.append(.init(icon: "filter_editor", name: "editor".localizedString, options: .filter(type: .editor)))
            filters.append(.init(icon: "filter_no_editor", name: "no_editor".localizedString, options: .filter(type: .noEditor)))
            if editorNameItems.count > 0 {
                filters.append(.init(icon: "filter_name", name: "editor_name".localizedString, options: .section(items: editorNameItems)))
            }
            if visitorNameItems.count > 0 {
                filters.append(.init(icon: "filter_name", name: "visitor_name".localizedString, options: .section(items: visitorNameItems)))
            }
            filters.append(.init(icon: "filter_password", name: "visitor_password".localizedString, options: .filter(type: .visitorPassword)))
            filters.append(.init(icon: "filter_no_password", name: "no_visitor_password".localizedString, options: .filter(type: .noVisitorPassword)))
            filters.append(.init(icon: "filter_device_exists", name: "devices_exists".localizedString, options: .filter(type: .devicesExists)))
            filters.append(.init(icon: "filter_no_device", name: "filter_no_devices".localizedString, options: .filter(type: .noDevices)))
            return filters
        }
        
        /// editor角色筛选条件
        static func editorDefalutFilters() -> [FilterData] {
            var filters: [FilterData] = []
//            filters.append(.init(icon: "filter_all", name: "all_space".localizedString, options: .filter(type: .none)))
            filters.append(.init(icon: "filter_favorite", name: "favorite_space".localizedString, options: .filter(type: .favorite)))
            filters.append(.init(icon: "filter_editor", name: "editor".localizedString, options: .filter(type: .isEditor)))
            filters.append(.init(icon: "filter_isVisitor", name: "visitor".localizedString, options: .filter(type: .isVisitor)))
            filters.append(.init(icon: "filter_password", name: "visitor_password".localizedString, options: .filter(type: .visitorPassword)))
            filters.append(.init(icon: "filter_no_password", name: "no_visitor_password".localizedString, options: .filter(type: .noVisitorPassword)))
            filters.append(.init(icon: "filter_device_exists", name: "devices_exists".localizedString, options: .filter(type: .devicesExists)))
            filters.append(.init(icon: "filter_no_device", name: "filter_no_devices".localizedString, options: .filter(type: .noDevices)))
            return filters
        }
        
    }
    
    
    
    enum Options {
        case allSpace
        case favoriteSpace
        /// 有子管理员
        case editor
        /// 没有子管理员
        case noEditor
        /// 自己是子管理员
        case isEditor
        /// 自己是访客
        case isVisitor
        /// 子管理名称section
        case editorNameSection
        /// 子管理员名称为"?"
        case editorName(name: String)
        /// 访客名称section
        case visitorNameSection
        /// 访客名称为"?"
        case visitorName(name: String)
        /// 有访客密码的
        case visitorPassword
        /// 没有访客密码的'
        case noVisitorPassword
        /// 有设备的
        case devicesExists
        /// 没有设备的
        case noDevices
    }
    
    /// 筛选条件
    enum FilterType {
        
        static func == (lhs: FilterType, rhs: FilterType) -> Bool {
            return lhs.rawValue == rhs.rawValue && lhs.name == rhs.name
        }
        
        /// 名称（仅名称筛选有值）
        var name: String? {
            switch self {
            case .editorName(let name):
                return name
            case .visitorName(let name):
                return name
            default:
                return nil
            }
        }
        
        /// 对应类型值
        var rawValue: Int {
            switch self {
            case .favorite:
                return 1
            case .editor:
                return 2
            case .noEditor:
                return 3
            case .isEditor:
                return 4
            case .isVisitor:
                return 5
            case .editorName:
                return 6
            case .visitorName:
                return 7
            case .visitorPassword:
                return 8
            case .noVisitorPassword:
                return 9
            case .devicesExists:
                return 10
            case .noDevices:
                return 11
            }
        }
        
        /// 无（所有）
//        case none
        /// 喜欢的
        case favorite
        /// 有子管理员
        case editor
        /// 没有子管理员
        case noEditor
        /// 自己是子管理员
        case isEditor
        /// 自己是访客
        case isVisitor
        /// 子管理员名称为"?"
        case editorName(name: String)
        /// 访客名称为"?"
        case visitorName(name: String)
        /// 有访客密码的
        case visitorPassword
        /// 没有访客密码的'
        case noVisitorPassword
        /// 有设备的
        case devicesExists
        /// 没有设备的
        case noDevices
    }
    
}

class ShareAuthorityFilterHeaderView: UITableViewHeaderFooterView {
    
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var arrowImageView: UIImageView!
    var lineView: UIView!
    
    var clickActionCallback: (()->Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClickAction)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewClickAction() {
        clickActionCallback?()
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(2))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(iconImageView)
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_right_black"))
        arrowImageView.isHidden = true
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color.withAlphaComponent(0.5)
        lineView.isHidden = true
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
}
