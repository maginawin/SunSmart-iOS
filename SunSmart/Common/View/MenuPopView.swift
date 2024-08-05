//
//  MenuPopView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/20.
//

import UIKit

class MenuPopView: UIView {

    /// 默认菜单内容宽度
    static let defalutMenuWidth = SCRXFrom(108)
    /// 默认item高度
    static let defalutItemHeight = SCRYFrom(36)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var bubbleView: UIImageView!
    private var effectView: UIVisualEffectView!
    private var tableView: UITableView!
    
    private var items: [MenuItem] = []
    private var startPoint: CGPoint = .zero
    private var menuWidth: CGFloat = 0
    private var itemHeight: CGFloat = 0
    private var isShow: Bool = false
    
    static func show(items: [MenuItem], anchorPoint: CGPoint, menuWidth: CGFloat = MenuPopView.defalutMenuWidth, itemHeight: CGFloat = MenuPopView.defalutItemHeight) {
//        let itemHeight: CGFloat =
        let view = MenuPopView(frame: UIScreen.main.bounds)
        view.menuWidth = menuWidth
        view.itemHeight = itemHeight
        view.startPoint = anchorPoint
        view.items = items
        view.setupUI()
        UIApplication.shared.keyWindow().addSubview(view)
        
        view.showAnimation()
    }
    
    static func hide() {
        if let popView = UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: self.classForCoder()) }) as? MenuPopView {
            popView.dismiss()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        if isShow {
            showAnimation()
        }
    }

    private func showAnimation() {
        layoutIfNeeded()
       
        var contentPoint = CGPoint(x: self.startPoint.x + SCRXFrom(15), y: self.startPoint.y)
        
        var anchorPoint = CGPointMake(1, 0)
        if startPoint.y + contentView.height > self.height { // 超出显示范围
            // 弹出方向调整
            anchorPoint = CGPointMake(1, 1)
            // 图片翻转
            var bubbleImage = bubbleView.image!
            if startPoint.y + contentView.height > self.height {
                bubbleImage = UIImage.init(cgImage: bubbleImage.cgImage!, scale: bubbleImage.scale, orientation: .downMirrored)
            }
            bubbleImage = bubbleImage.resizableImage(withCapInsets: UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(20), bottom: SCRYFrom(20), right: SCRXFrom(40)), resizingMode: .stretch)
            bubbleView.image = bubbleImage
            tableView.snp.updateConstraints { make in
                make.top.equalTo(SCRYFrom(5))
                make.bottom.equalTo(SCRYFrom(-12))
            }
            contentPoint = CGPoint(x: contentPoint.x, y: contentPoint.y - SCRYFrom(25))
        }
        contentView.layer.anchorPoint = anchorPoint
        contentView.transform = CGAffineTransformMakeScale(0.01, 0.01)
        self.contentView.frame.origin = contentPoint
        UIView.animate(withDuration: 0.3) {
            self.contentView.transform = CGAffineTransformIdentity;
        } completion: { _ in
            self.isShow = true
        }
    }
    
    func dismiss() {
        isShow = false
        contentView.layer.anchorPoint = contentView.layer.anchorPoint
        UIView.animate(withDuration: 0.3) {
            self.contentView.transform = CGAffineTransformMakeScale(0.01, 0.01)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func shadeViewClick() {
        dismiss()
    }
    
    
    private func setupUI() {
        
        shadeView = UIView(frame: self.bounds)
//        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        let tap = UITapGestureRecognizer(target: self, action: #selector(shadeViewClick))
        tap.delegate = self
        shadeView.addGestureRecognizer(tap)
        addSubview(shadeView)
        
        contentView = UIView()
//        contentView.backgroundColor = RGB(0, 0, 0, 0.6)
//        contentView.layer.cornerRadius = 12
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.width.equalTo(menuWidth)
        }

        bubbleView = UIImageView()
        var bubbleImage = UIImage(named: "menu_bubble")!
        bubbleImage = bubbleImage.resizableImage(withCapInsets: UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(20), bottom: SCRYFrom(20), right: SCRXFrom(40)), resizingMode: .stretch)
        bubbleView.image = bubbleImage
        contentView.addSubview(bubbleView)
        bubbleView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = itemHeight
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.isScrollEnabled = false
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-5))
            make.height.equalTo(CGFloat(items.count) * itemHeight)
        }
    }
}

extension MenuPopView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        cell.backgroundColor = .clear
        let item = items[indexPath.row]
        cell.titleLabel.text = item.title
        cell.titleLabel.textColor = .white
        cell.titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        cell.iconImageView.image = item.icon
        cell.iconX = 0
        cell.iconSize = CGSize(width: SCRXFrom(30), height: SCRXFrom(30))
        cell.titleX = SCRXFrom(35)
        cell.lineView.isHidden = true
        cell.arrowImageView.isHidden = true
        cell.layer.cornerRadius = 5
        cell.clipsToBounds = true
        cell.selectionStyle = .gray
//        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        item.tapItemBack?(item)
        dismiss()
    }
    
}

extension MenuPopView: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        if let view = touch.view, NSStringFromClass(view.classForCoder) == "UITableViewCellContentView" {
            return false
        }
        return true
    }
}

extension MenuPopView {
    
    struct MenuItem {
        let icon: UIImage?
        let title: String
        let tapItemBack: ((MenuItem)->Void)?
    }
    
}
