//
//  GroupFilterSelectView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit
import NordicSigMeshSDK

class GroupFilterSelectView: UIView {
    
    typealias FilterSelectCallback = ((GroupFilterSelectView.FilterType?)->Void)
    
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
            case .group(let group):
                self.filters.enumerated().forEach { (sectionIndex, filter) in
                    if case .section(let items) = filter.options {
                        if let item = items.first(where: {// $0.filterType! == type
                            if case .group(let filterGroup) = $0.filterType! {
                                return filterGroup == group
                            }
                            return false
                        }) {
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
        tableView.rowHeight = SCRYFrom(36)
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

extension GroupFilterSelectView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return filters.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == 0 || section == 1 {
            return SCRYFrom(8)
        }
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let filter = filters[indexPath.section]
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
        
        if indexPath.section == 0 || indexPath.section == 1 {
            cell.backgroundColor = RGB(216, 216, 216, 0.1)
            cell.selectionStyle = .none
        }else {
            cell.backgroundColor = .clear
            cell.selectionStyle = .gray
        }
        
        cell.layer.cornerRadius = 8
        cell.clipsToBounds = true
        cell.lineView.isHidden = true
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let filter = filters[indexPath.section]
        
        switch filter.options {
        case .filter(let type):
            selectCallback?(type)
            hide()
        case .section(let items):
            // 是否展开
            if filter.spread {
//                var indexPaths: [IndexPath] = []
                items.enumerated().forEach { (index, item) in
                    filters.remove(at: indexPath.section + 1)
//                    indexPaths.append(IndexPath(row: 0, section: indexPath.section + 1 + index))
                }
                // 展开状态点击后收起，删除展开的数据
//                tableView.deleteRows(at: indexPaths, with: .automatic)
            }else {
                // 收起状态点击后展开，显示展开的数据
//                var indexPaths: [IndexPath] = []
                items.enumerated().forEach { (index, item) in
                    filters.insert(item, at: indexPath.section + index + 1)
//                    indexPaths.append(IndexPath(row: 0, section: indexPath.section + 1 + index))
                }
//                tableView.insertRows(at: indexPaths, with: .automatic)
            }
            filter.spread = !filter.spread
            
            tableView.reloadData()
            
//            if let cell = tableView.cellForRow(at: indexPath) as? CustomTableViewCell {
//                cell.arrowImageView.image = UIImage(named: filter.spread ? "arrow_down_black" : "arrow_right_black")
//            }
            
        }
        
    }
    
}
    

extension GroupFilterSelectView {
    
    /// 筛选条件
    enum FilterType {
        
        static func == (lhs: FilterType, rhs: FilterType) -> Bool {
            guard lhs.rawValue == rhs.rawValue else {
                return false
            }
            if case .group(let group1) = lhs, case .group(let group2) = rhs {
                return group1.address == group2.address
            }
            return true
        }
        
        /// 对应类型值
        var rawValue: Int {
            switch self {
            case .notInGroup:
                return 1
            case .group:
                return 2
            }
        }
        
        /// 未加入组
        case notInGroup
        /// 对应组
        case group(_ group: Group)
    }
    
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
        static func defalutFilters(groups: [Group]) -> [FilterData] {
            
            let groupItems = groups.map({ FilterData(icon: nil, name: $0.name, options: .filter(type: .group($0))) })
            
            var filters: [FilterData] = []
            filters.append(.init(icon: "filter_not_in_group", name: "not_in_group".localizedString, options: .filter(type: .notInGroup)))
            if groupItems.count > 0 {
                filters.append(.init(icon: "filter_in_group", name: "group".localizedString, options: .section(items: groupItems)))
            }
            return filters
        }
    }
    
}
