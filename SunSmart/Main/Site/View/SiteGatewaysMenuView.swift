//
//  SiteGatewaysMenuView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/24.
//

import UIKit

class SiteGatewaysMenuView: UIView {

    struct GatewayMenuData {
        /// 名称
        let name: String
        /// 状态
        let status: GatewayConnectStatus
    }
    
    /// 默认内容宽度
    static let defalutWidth = SCRXFrom(164)
    /// 默认item高度
    static let defalutItemHeight = SCRYFrom(36)
    /// 选择回调
    typealias MenuSelectCallback = ((Int)->Void)
    /// 添加点击回调
    typealias MenuAddCallback = (()->Void)
    /// 关闭回调
    typealias HideCallback = (()->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var tableView: UITableView!
    
    private var datas: [GatewayMenuData] = []
    private var startPoint: CGPoint = .zero
    private var selectIndex: Int?
    private var menuWidth: CGFloat = defalutWidth
    private var itemHeight: CGFloat = defalutItemHeight
    private var selectCallback: MenuSelectCallback?
    private var hideCallback: HideCallback?
    private var addCallback: MenuAddCallback?
    private var selectBackgroundColor: UIColor = RGB(216, 216, 216, 0.1)
    private var titleColor: UIColor = .white
    private var titleFont: UIFont = FONTS(13)
    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
    
    static func show(datas: [GatewayMenuData], anchorPoint: CGPoint, selectIndex: Int? = nil, menuWidth: CGFloat = SiteGatewaysMenuView.defalutWidth, itemHeight: CGFloat = TitleSelectView.defalutItemHeight, titleColor: UIColor = .white, titleFont: UIFont = FONTS(13), backgroundColor: UIColor = RGB(102, 102, 102), selectBackgroundColor: UIColor = RGB(216, 216, 216, 0.1), shadowColor: UIColor? = nil, selectBack: MenuSelectCallback?, addCallback: MenuAddCallback?, hideCallback: HideCallback? = nil) {
        
        let view = SiteGatewaysMenuView(frame: UIScreen.main.bounds)
        view.menuWidth = menuWidth
        view.itemHeight = itemHeight
        view.startPoint = anchorPoint
        view.selectIndex = selectIndex
        view.datas = datas
        view.titleFont = titleFont
        view.titleColor = titleColor
        view.selectBackgroundColor = selectBackgroundColor
        view.selectCallback = selectBack
        view.hideCallback = hideCallback
        view.addCallback = addCallback
        view.setupUI()
        view.contentView.backgroundColor = backgroundColor
        if shadowColor != nil {
            view.contentView.layer.shadowColor = shadowColor!.cgColor
            view.contentView.layer.shadowOpacity = 1
            view.contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.contentView.layer.cornerRadius = 6
        }
        view.tag = 100
        UIApplication.shared.keyWindow().addSubview(view)
        view.showAnimation()
    }
    
    private func showAnimation() {
        
        layoutIfNeeded()
        
//        contentView.layer.anchorPoint = anchorPoint
        contentView.alpha = 0
//        contentView.transform = CGAffineTransformMakeScale(0.01, 0.01)
//        self.contentView.frame.origin = contentPoint
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 1
        } completion: { _ in
            if self.tableView.firstShowFlashScrollIndicators {
                self.tableView.flashScrollIndicatorsIfNeeded()
            }
        }
    }
    
    func dismiss() {
        
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
        
        hideCallback?()
    }
    
    @objc private func shadeViewClick() {
        dismiss()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(102, 102, 102)
        contentView.layer.cornerRadius = 8
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
//            make.top.centerX.equalToSuperview()
            make.top.equalTo(startPoint.y)
            make.left.equalTo(startPoint.x)
            make.width.equalTo(menuWidth)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.rowHeight = itemHeight
//        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = datas.count + 1 > 8
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(4)
            make.right.equalTo(-4)
            make.top.equalTo(4)
            make.bottom.equalTo(-6)
            make.height.equalTo(CGFloat(min(datas.count + 1, 8)) * tableView.rowHeight)
        }
        
    }
    
}

extension SiteGatewaysMenuView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return datas.count + 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        
        if indexPath.row == datas.count {
            cell.cellStyle = .none
            cell.titleX = SCRXFrom(8)
            cell.titleLabel.text = "＋" + "add_gateway".localizedString
        }else {
            
            let data = datas[indexPath.row]
            cell.cellStyle = .icon
            switch data.status {
            case .online:
                cell.iconImageView.image = UIImage(named: "gateway_status_online")
            case .offline, .reset:
                cell.iconImageView.image = UIImage(named: "gateway_status_online")?.withTintColor(RGB(200, 200, 200))
            case .inactive:
                cell.iconImageView.image = UIImage(named: "gateway_status_online")?.withTintColor(Yellow_Color)
            }
            cell.iconX = SCRXFrom(8)
            cell.titleX = SCRXFrom(22)
            cell.titleLabel.text = data.name
        }
        cell.titleLabel.textColor = titleColor
        cell.titleLabel.font = titleFont
        cell.backgroundColor = selectIndex == indexPath.row ? self.selectBackgroundColor : .clear
        cell.titleMaxWidth = tableView.width - SCRXFrom(26)
        cell.lineView.isHidden = !(indexPath.row == datas.count - 1)
        cell.lineX = 0
        cell.lineView.backgroundColor = Line_Color.withAlphaComponent(0.5)
        cell.arrowImageView.isHidden = true
        cell.layer.cornerRadius = 5
//        cell.clipsToBounds = true
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == datas.count {
            addCallback?()
        }else {
            selectCallback?(indexPath.row)
        }
        dismiss()
    }
}
