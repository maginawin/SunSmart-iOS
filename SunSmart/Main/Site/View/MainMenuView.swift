//
//  MainMenuView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/20.
//

import UIKit
import SnapKit

class MainMenuView: UIView {

    typealias MenuTapActionCallback = (Int)->Void
    
    private var contentView: UIView!
    private var logoImageView: UIImageView!
    private var titleLabel: UILabel!
    private var lineView: UIView!
    private var tableView: UITableView!
    private var versionLabel: UILabel!
    
    private var shadeView: UIView!
    
    private var menuTapBack: MenuTapActionCallback?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    static func show(menuTap: MenuTapActionCallback? = nil) {
        
        let menuView = MainMenuView(frame: UIScreen.main.bounds)
        menuView.menuTapBack = menuTap
        UIApplication.shared.keyWindow().addSubview(menuView)
//        UIViewController.getVisibleVc()?.navigationController?.view.addSubview(menuView)
        menuView.showAnimation()
    }
    
    static func hide() {
        if let menuView = UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: self.classForCoder()) }) as? MainMenuView {
            menuView.dismiss()
        }
    }
    
    private func showAnimation() {
        
        self.layoutIfNeeded()
        self.shadeView.alpha = 0
        self.contentView.x = -self.contentView.width
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.x = 0
        }
    }
    
    @objc private func dismiss() {
        
        self.layoutIfNeeded()
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.x = -self.contentView.width
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    private func test() {
        
//        private var leftView: UIView!
//        private var shadeView: UIView!
//
//        private var scrollView: UIScrollView!
//
//        private var lastPoint: CGPoint?
//
//        private var showMenu: Bool = false
        
//        scrollView = UIScrollView(frame: view.bounds)
//        scrollView.contentSize = CGSize(width: view.width * 2, height: view.height)
//        scrollView.isPagingEnabled = true
//        scrollView.bounces = false
//        scrollView.delegate = self
//        view.addSubview(scrollView)
        
//        shadeView = UIView(frame: view.bounds)
//        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
//        shadeView.alpha = 0
//        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
//        view.addSubview(shadeView)
//
//        let leftViewW = view.width * 0.7
//        leftView = UIView(frame: CGRect(x: -leftViewW, y: 0, width: leftViewW, height: view.height))
//        leftView.backgroundColor = Red_Color
//        view.addSubview(leftView)
//
//
//        let pan = UIPanGestureRecognizer(target: self, action: #selector(panGestureEvent))
//        pan.delegate = self
//        pan.cancelsTouchesInView = false
//        view.addGestureRecognizer(pan)
     
//        @objc private func panGestureEvent(sender: UIPanGestureRecognizer) {
//            
//            switch sender.state {
//            case .began:
//                lastPoint = sender.translation(in: view)
//                scrollView.isScrollEnabled = false
//            case .changed:
//                //            let translationPoint = sender.translation(in: view)
//                let touchPoint = sender.location(in: view)
//                
//                let point = sender.translation(in: view)
//                // 超出滑动范围
//                if leftView.frame.maxX > 0 && touchPoint.x > leftView.frame.width {
//                    lastPoint = point
//                    return
//                }
//                
//                var leftViewX = leftView.x
//                leftViewX += point.x - (lastPoint?.x ?? 0)
//                
//                print("move point: \(leftViewX)")
//                //            let moveX = min(leftViewX, view.width * 0.7)
//                leftView.x = min(leftViewX, 0)
//                lastPoint = point
//                
//                let alpha = leftView.frame.maxX / leftView.width
//                shadeView.alpha = alpha
//                
//            case .ended, .cancelled:
//                let maxX = leftView.frame.maxX
//                if maxX > 0 {
//                    // 滑动速度
//                    let velocityX = sender.velocity(in: view).x
//                    // 是否强力滑动
//                    let isStrong = abs(velocityX) > 800
//                    // 目标位置
//                    var targetX: CGFloat = 0
//                    if isStrong {
//                        // 强力滑动时判断是左/右滑动，设置到对应位置
//                        targetX = velocityX > 0 ? 0 : -leftView.width
//                    }else {
//                        // 非强力滑动时以具体位置为参考，超出一半宽度则展开，不超出则隐藏
//                        if maxX < leftView.width * 0.5 {
//                            targetX = -leftView.width
//                        }
//                    }
//                    drawerWithChange(targetX: targetX)
//                    lastPoint = nil
//                }
//                scrollView.isScrollEnabled = true
//            default:
//                break
//            }
//            
//        }
//        
//        private func drawerWithChange(targetX: CGFloat) {
//            UIView.animate(withDuration: 0.3, delay: 0.05, usingSpringWithDamping: 1, initialSpringVelocity: 0.3) {
//                self.leftView.x = targetX
//                
//                let alpha = self.leftView.frame.maxX / self.leftView.width
//                self.shadeView.alpha = alpha
//            }
//        }
//        
//        @objc private func shadeViewClick() {
//            drawerWithChange(targetX: -leftView.width)
//        }
        
//        extension MainViewController: UIGestureRecognizerDelegate {
//
//            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
//
//                let point = gestureRecognizer.location(in: view)
//
//                if view.window == nil || (leftView.frame.maxX <= 0 && point.x > 50) {
//                    return false
//                }
//                return true
//            }
//
//            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//
//                return true
//            }
//
//        }

        
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(288.0 / 375.0)
        }
        
        logoImageView = UIImageView(image: UIImage(named: "launch_logo"))
        logoImageView.backgroundColor = Background_Color
        contentView.addSubview(logoImageView)
        logoImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(kNavigationHeight)
            make.width.height.equalTo(SCRYFrom(120))
        }
        
        titleLabel = UILabel(text: "Sunsmart", textColor: Bar_Color, fontSize: 15, fontName: FontName_Medium)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalTo(logoImageView)
            make.top.equalTo(logoImageView.snp.bottom).offset(SCRYFrom(9))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(50))
            make.height.equalTo(1)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.rowHeight = SCRYFrom(44)
        tableView.dataSource = self
        tableView.backgroundColor = RGB(248, 250, 252)
        tableView.delegate = self
        tableView.isScrollEnabled = false
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(lineView.snp.bottom)
        }
        
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        versionLabel = UILabel(text: "Version \(version)", textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(versionLabel)
        versionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(SCRYFrom(-34))
        }
    }
    
}

extension MainMenuView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .arrow
        cell.titleLabel.text = "About"
        cell.titleLabel.font = Font_Medium_Size(15)
        cell.titleLabel.textColor = TextBlack_Color
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        menuTapBack?(indexPath.row)
        dismiss()
    }
}
