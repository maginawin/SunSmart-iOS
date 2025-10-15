//
//  TableSelectView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/4.
//

import UIKit

class TableSelectView: UIView {

    /// 默认内容宽度
    static let defalutWidth = SCRXFrom(164)
    /// 默认item高度
    static let defalutItemHeight = SCRYFrom(36)
    /// 选择回调
    typealias TitleSelectCallback = ((Int)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var tableView: UITableView!
    
    private var items: [TableItem] = []
    private var startPoint: CGPoint = .zero
    private var selectIndex: Int = 0
    private var menuWidth: CGFloat = defalutWidth
    private var itemHeight: CGFloat = defalutItemHeight
    private var selectBackgroundColor: UIColor = RGB(216, 216, 216, 0.1)
    private var titleColor: UIColor = .white
    private var titleFont: UIFont = FONTS(13)
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
    
    static func show(items: [TableItem], anchorPoint: CGPoint, selectIndex: Int = 0, menuWidth: CGFloat = TitleSelectView.defalutWidth, itemHeight: CGFloat = TitleSelectView.defalutItemHeight, titleColor: UIColor = .white, titleFont: UIFont = FONTS(13), backgroundColor: UIColor = RGB(102, 102, 102), selectBackgroundColor: UIColor = RGB(216, 216, 216, 0.1), shadowColor: UIColor? = nil) {
        
        let view = TableSelectView(frame: UIScreen.main.bounds)
        view.menuWidth = menuWidth
        view.itemHeight = itemHeight
        view.startPoint = anchorPoint
        view.selectIndex = selectIndex
        view.items = items
        view.titleFont = titleFont
        view.titleColor = titleColor
        view.selectBackgroundColor = selectBackgroundColor
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
        }
    }
    
    func dismiss() {
        
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
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
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = items.count > 8
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(4)
            make.right.equalTo(-4)
            make.top.equalTo(4)
            make.bottom.equalTo(-6)
            make.height.equalTo(CGFloat(min(items.count, 8)) * tableView.rowHeight)
        }
        
    }

}

extension TableSelectView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        let item = items[indexPath.row]
        cell.titleLabel.text = item.title
        cell.titleLabel.textColor = titleColor
        cell.titleLabel.font = titleFont
        cell.iconImageView.image = item.icon
        cell.iconX = 0
        cell.titleX = SCRXFrom(35)
        cell.lineView.isHidden = true
        cell.arrowImageView.isHidden = true
        cell.layer.cornerRadius = 5
        cell.clipsToBounds = true
        cell.selectionStyle = .none
//        let bgView = UIView()
//        bgView.backgroundColor = RGB(216, 216, 216, 0.1)
//        cell.selectedBackgroundView = bgView
        cell.backgroundColor = selectIndex == indexPath.row ? self.selectBackgroundColor : .clear
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        item.tapItemBack?(item)
        dismiss()
    }
}

extension TableSelectView {
    
    struct TableItem {
        let icon: UIImage?
        let title: String
        let tapItemBack: ((TableItem)->Void)?
    }
    
}
