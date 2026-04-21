//
//  EmerFireAlarmMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit

class EmerFireAlarmMonitorVC: UIViewController {
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var deviceCountLabel: UILabel!
    private var pageControl: UIPageControl!
    /// 列数
    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 6 : 3
    
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFrom(36), right: SCRXFrom(24))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    //操作按钮
    
    private var groups: [String] = []
    
    private lazy var moniView: EmerFireAlarmMoniView = {
        let view = EmerFireAlarmMoniView()
        return view
    }()

    private lazy var statusSetView: EmerFireAlarmStatusSetView = {
        let view = EmerFireAlarmStatusSetView()
        view.title = "Status Set".localizedString
        return view
    }()
    lazy var statusLab : EmerFireAlarmMoniHead = {
        var view = EmerFireAlarmMoniHead()
        view.frame = CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFit(45))
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "EFC 1"
        
        view.backgroundColor = Background_Color
        
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            
            navigationController?.setNavigationBarBackgroundColor(color: .clear)

            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        
        // 添加左滑手势
        let previousSwipe = UISwipeGestureRecognizer(target: self, action: #selector(groupPreviousSwipeAction))
        previousSwipe.direction = .right
        view.addGestureRecognizer(previousSwipe)
        // 添加右滑手势
        let nextSwipe = UISwipeGestureRecognizer(target: self, action: #selector(groupNextSwipeAction))
        nextSwipe.direction = .left
        view.addGestureRecognizer(nextSwipe)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        setTestData()
        applySavedConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigDidChange(_:)), name: .linkedEmerFireConfigDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func groupPreviousSwipeAction() {
        XWHUDManager.showTipHUD("dev1", isLineFeed: true)
    }
    
    @objc private func groupNextSwipeAction() {
        
    }
    
    @objc private func close() {

        self.dismissLikeSystem()
        
    }
    
    func setTestData(){
        moniView.configure(actions: [
            .init(
                image: UIImage(named: "icon"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Manual emergency", isLineFeed: false)
                }
            ),
            .init(
                image: UIImage(named: "Logout-2 Streamline Sharp1"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Previous action", isLineFeed: false)
                }
            ),
            .init(
                image: UIImage(named: "Logout-2 Streamline Sharp"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Next action", isLineFeed: false)
                }
            )
        ])
        statusSetView.headerActionHandler = { action in
            let message: String
            switch action {
            case .alert:
                message = "Alert action"
            case .statusGray:
                message = "Gray status action"
            case .fire:
                message = "Fire action"
            case .statusGreen:
                message = "Green status action"
            }
            XWHUDManager.showTipHUD(message, isLineFeed: false)
        }
        updateEmptyUI()
    }
    
    func setupUI(){
        
        view.addSubview(statusLab)
        statusLab.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(10))
            make.left.right.equalToSuperview()
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemRowCount = rowNum
        flowLayout.itmeColCount = columnNum
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: collectionViewInsets.left, bottom: 0, right: collectionViewInsets.right)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: collectionViewInsets.bottom, left: 0, bottom: collectionViewInsets.bottom, right: 0)
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(EmerFireAlarmMoniCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            if isIPad {
                make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(60))
                make.height.equalTo(SCRYFrom(498))
            }else {
                make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(40))
                make.height.equalTo(SCRYFrom(340))
            }
        }
        
        deviceCountLabel = UILabel(text: "", textColor: Bar_Color, fontSize: 14, fontWeight: .light)
        view.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView).offset(SCRXFrom(20))
            make.top.equalTo(collectionView).offset(SCRYFrom(13))
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
        }
        view.addSubview(moniView)
        moniView.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFrom(100))
            make.left.equalToSuperview().offset(SCRYFrom(56))
            make.right.equalToSuperview().offset(-SCRYFrom(56))
        }
        view.addSubview(statusSetView)
        statusSetView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }
        
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: self.collectionView.contentOffset.y), animated: true)
    }
    
    @objc private func moreClick() {
        
        var items: [MenuPopView.MenuItem] = []

            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                let controller = LinkedEmerFireEditVC(config: LinkedEmerFireStore.shared.currentConfig)
                controller.editable = true
                let navigationController = NavigationViewController(rootViewController: controller)
                self?.present(navigationController, animated: true)
            }))
        
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { item in
                
                XWHUDManager.showTipHUD("delete", isLineFeed: false)
            }))
        
          items.append(.init(icon: UIImage(named: "info"), title: "information".localizedString, tapItemBack: {[weak self] item in
            
             // XWHUDManager.showTipHUD("information", isLineFeed: false)
              
              let controller = EmerFireAlarmInformationVC()
              let navigationController = NavigationViewController(rootViewController: controller)
              self?.present(navigationController, animated: true)
              
          }))
        
           items.append( .init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: { item in
               XWHUDManager.showTipHUD("refresh", isLineFeed: false)
            }))
        
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10

        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(128))
       
    }
    
    private func updateEmptyUI() {
        if groups.isEmpty {
            deviceCountLabel.isHidden = true
            if collectionView.frame == .zero {
                view.layoutIfNeeded()
            }
            if collectionView.emptyView == nil {
                collectionView.showEmptyDataView(title: "Not associate with Group(s) !".localizedString, buttonText: "Setting".localizedString, position: .center) {
                    //
                    XWHUDManager.showTipHUD("Setting", isLineFeed: false)
                }
                if let emptyView = collectionView.emptyView {
                    
                        emptyView.button.backgroundColor = .clear
                        emptyView.button.titleLabel?.font = FONTS(16)
                        emptyView.button.setTitleColor(Bar_Color, for: .normal)
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                        }
                    
                      //  emptyView.button.isHidden = true
                    
                }
            }
        }else {
            deviceCountLabel.isHidden = false
            collectionView.hideEmptyDataView()
        }
    }

    @objc private func handleConfigDidChange(_ notification: Notification) {
        applySavedConfig()
    }

    private func applySavedConfig() {
        guard let config = LinkedEmerFireStore.shared.currentConfig else {
            title = "EFC 1"
            groups = []
            deviceCountLabel.text = "(0)"
            collectionView?.reloadData()
            updateEmptyUI()
            return
        }

        title = config.deviceName
        groups = makeDisplayGroups(from: config)
        deviceCountLabel.text = "(\(groups.count))"
        collectionView?.reloadData()
        updateEmptyUI()
    }

    private func makeDisplayGroups(from config: LinkedEmerFireConfig) -> [String] {
        var displayGroups: [String] = []

        let state = LinkedEmerFireEditState(config: config)
        let powerLossGroups = state.groupText(for: .powerLossGroups)
        let fireAlarmGroups = state.groupText(for: .fireAlarmGroups)

        [powerLossGroups, fireAlarmGroups]
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { !$0.isEmpty }
            .forEach { group in
                if !displayGroups.contains(group) {
                    displayGroups.append(group)
                }
            }

        return displayGroups
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            XWHUDManager.showTipHUD("\(indexPath.row)", isLineFeed: true)
        }
    }
    
}


extension EmerFireAlarmMonitorVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmerFireAlarmMoniCell
        cell.configure(title: groups[indexPath.row])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        
    }
    

}
