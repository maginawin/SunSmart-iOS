//
//  GatewayAPNMenuView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/31.
//

import UIKit

class GatewayAPNMenuView: UIView {

    typealias APNSelectCallback = ((String) -> Void)
    
    /// 默认内容宽度
    static let defalutWidth = SCRXFrom(164)

    private var onItemSelected: APNSelectCallback?
    
    private var menuItems: [APNMenuItem] = []
    
    private var shadeView: UIView!
    private var contentView: UIView!
    
    private var tableView: UITableView!
    private var selectApnName: String?
    private let showPoint: CGPoint
    
    init(menuItems: [APNMenuItem], selectApnName: String?, showPoint: CGPoint, selectCallback: APNSelectCallback?) {
        self.showPoint = showPoint
        
        if selectApnName != nil {
            let item = menuItems.first(where: { $0.children?.contains(selectApnName!) ?? false })
            item?.isExpanded = true
        }
        
        super.init(frame: UIScreen.main.bounds)
        self.selectApnName = selectApnName
        self.menuItems = menuItems
        setupUI()
        onItemSelected = selectCallback
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        contentView.alpha = 0
//        contentView.transform = CGAffineTransformMakeScale(0.01, 0.01)
//        self.contentView.frame.origin = contentPoint
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 1
        }
    }
    
    @objc private func dismiss() {
        
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(98, 99, 100)
        contentView.layer.cornerRadius = SCRYFrom(8)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.top.equalTo(showPoint.y)
            make.left.equalTo(showPoint.x)
            make.width.equalTo(Self.defalutWidth)
            make.height.equalTo(SCRYFrom(221))
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.register(ShareAuthorityFilterHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(9))
            make.bottom.equalTo(SCRYFrom(-9))
        }
    }
    
}

extension GatewayAPNMenuView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return menuItems.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let data = menuItems[section]
        return data.isExpanded ? data.children?.count ?? 0 : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        let data = menuItems[indexPath.section]
        let name = data.children?[indexPath.row]
        cell.titleLabel.text = name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.titleLabel.numberOfLines = 2
        cell.titleLabel.textColor = .white
        cell.titleX = SCRXFrom(35)
        cell.iconImageView.image = UIImage(named: "server_select")?.withTintColor(.white)
        cell.iconImageView.isHidden = name != selectApnName
        cell.iconX = SCRXFrom(4)
        cell.arrowImageView.isHidden = true
        cell.titleMaxWidth = tableView.width * 0.8
        cell.lineView.isHidden = true
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! ShareAuthorityFilterHeaderView
        let data = menuItems[section]
        headerView.iconImageView.isHidden = true
        headerView.nameLabel.text = data.title
        headerView.nameLabel.textColor = .white
        headerView.arrowImageView.image = UIImage(named: data.isExpanded ? "arrow_up_black" : "arrow_right_black")?.withTintColor(.white)
        headerView.arrowImageView.isHidden = data.children?.isEmpty ?? true
        headerView.backgroundColor = RGB(98, 99, 100)
//        if !data.isExpanded, let selectApnName = self.selectApnName, data.children?.contains(selectApnName) ?? false {
//            headerView.contentView.backgroundColor = RGB(216, 216, 216, 0.1)
//            headerView.contentView.layer.cornerRadius = SCRYFrom(10)
//        }else {
//            headerView.contentView.backgroundColor = .clear
//        }
        headerView.lineView.isHidden = !data.isExpanded
        
        headerView.clickActionCallback = {[weak self] in
            guard let self = self else { return }
            if data.children?.count ?? 0 > 0 {
                data.isExpanded = !data.isExpanded
                tableView.reloadSections(IndexSet(integer: section), with: .automatic)
            }else {
                self.selectApnName = data.title
                self.onItemSelected?(self.selectApnName!)
                self.dismiss()
            }
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(36)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SCRYFrom(34.6)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        tableView.deselectRow(at: indexPath, animated: true)
        let data = menuItems[indexPath.section]
        if let name = data.children?[indexPath.row] {
            selectApnName = name
            self.onItemSelected?(name)
        }
        dismiss()
//        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }
}


extension GatewayAPNMenuView {
    
    class APNMenuItem {
        let title: String
        let children: [String]?
        var isExpanded: Bool = false
        
        init(title: String, children: [String]?, isExpanded: Bool = false) {
            self.title = title
            self.children = children
            self.isExpanded = isExpanded
        }
    }
    
}
