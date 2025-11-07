//
//  GroupMenuView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/6.
//

import UIKit

class GroupMenuView: UIView {

    /// 默认菜单内容宽度
    static let defalutMenuWidth = SCRXFrom(100)
    /// 默认item高度
    static let defalutItemHeight = SCRYFrom(42)
    
    private var blurredImageView: UIImageView!
    private var groupImageView: UIImageView!
    private var menuView: UIView!
    private var tableView: UITableView!
    private var groupImage: UIImage?
    private var bgBlurredImage: UIImage?
    private var groupCenterPoint: CGPoint = .zero
    private var menuItems: [MenuPopView.MenuItem] = []
     
    private var menuWidth = GroupMenuView.defalutMenuWidth
    private var itemHeight = GroupMenuView.defalutItemHeight
    
    init(frame: CGRect, groupImage: UIImage, bgBlurredImage: UIImage, menuItems: [MenuPopView.MenuItem], groupCenterPoint: CGPoint, menuWidth: CGFloat = GroupMenuView.defalutMenuWidth, itemHeight: CGFloat = GroupMenuView.defalutItemHeight) {
        
        super.init(frame: frame)
        self.groupImage = groupImage
        self.bgBlurredImage = bgBlurredImage
        self.groupCenterPoint = groupCenterPoint
        self.menuWidth = menuWidth
        self.itemHeight = itemHeight
        self.menuItems = menuItems
        setupUI()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(close))
        tap.delegate = self
        addGestureRecognizer(tap)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(to view: UIView) {
        if self.superview == nil {
            view.addSubview(self)
            layoutIfNeeded()
            
            if menuView.frame.maxY > self.height {
                menuView.snp.remakeConstraints { make in
                    make.centerX.equalTo(groupImageView)
                    make.bottom.equalTo(groupImageView.snp.top).offset(SCRYFrom(-8))
                    make.width.equalTo(menuWidth)
                }
            }
        }
        
        blurredImageView.alpha = 0
        groupImageView.alpha = 0
        menuView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.blurredImageView.alpha = 1
            self.groupImageView.alpha = 1
            self.menuView.alpha = 1
        }
        
    }
    
    func dismiss(animation: Bool = true) {
//        isShow = false

        if animation {
            UIView.animate(withDuration: 0.3) {
                self.blurredImageView.alpha = 0
                self.groupImageView.alpha = 0
                self.menuView.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }else {
            self.removeFromSuperview()
        }
    }
    
    @objc private func close() {
        dismiss()
    }
    
    private func setupUI() {
        
        blurredImageView = UIImageView(image: bgBlurredImage)
        
        addSubview(blurredImageView)
        blurredImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
                
        groupImageView = UIImageView(image: groupImage)
        groupImageView.layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        groupImageView.layer.shadowOffset = CGSizeMake(0,2)
        groupImageView.layer.shadowOpacity = 1
        groupImageView.layer.shadowRadius = 4
//        groupImageView.frame = CGRect(x)
        addSubview(groupImageView)
        groupImageView.snp.makeConstraints { make in
            make.center.equalTo(groupCenterPoint)
        }
        
        menuView = UIView()
        menuView.backgroundColor = RGB(0, 0, 0, 0.6)
        menuView.layer.cornerRadius = SCRYFrom(8)
        menuView.layer.masksToBounds = true
        addSubview(menuView)
        menuView.snp.makeConstraints { make in
            make.centerX.equalTo(groupImageView)
            make.top.equalTo(groupImageView.snp.bottom).offset(SCRYFrom(8))
            make.width.equalTo(menuWidth)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = itemHeight
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.isScrollEnabled = false
        menuView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(4))
            make.bottom.equalTo(SCRYFrom(-4))
            make.height.equalTo(CGFloat(menuItems.count) * itemHeight)
        }
        
    }

}

extension GroupMenuView: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        if let view = touch.view, NSStringFromClass(view.classForCoder) == "UITableViewCellContentView" {
            return false
        }
        return true
    }
}

extension GroupMenuView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menuItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        cell.backgroundColor = .clear
        let item = menuItems[indexPath.row]
        cell.titleLabel.text = item.title
        cell.titleLabel.textColor = .white
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRXFrom(14), weight: .light)
        cell.iconImageView.image = item.icon
        cell.iconX = 0
        cell.iconSize = CGSize(width: SCRXFrom(30), height: SCRXFrom(30))
        cell.titleX = SCRXFrom(35)
        cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
        cell.lineX = 0
        cell.lineView.backgroundColor = .white.withAlphaComponent(0.2)
        cell.arrowImageView.isHidden = true
        cell.layer.cornerRadius = 5
        cell.clipsToBounds = true
        cell.selectionStyle = .gray
//        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = menuItems[indexPath.row]
        item.tapItemBack?(item)
        dismiss(animation: item.hideAnimation)
    }
    
}
