//
//  GroupViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit
import NordicSigMeshSDK

class GroupViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var onoffBtn: UIButton!
    private var lightnessSlider: BuoySliderView!
    private var cctSlider: BuoySliderView!
    private var pageControl: UIPageControl!
    
    let space: SpaceData
    let group: Group
    
    private var devices: [String] = []
    
    /// 组更新回调
    var groupUpdateCallback: ((Group)->Void)?
    /// 组删除回调
    var groupDeleteCallback: ((Group)->Void)?
    
    init(space: SpaceData,group: Group) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = group.name
        
        view.backgroundColor = Background_Color
        
        if self.presentingViewController != nil {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .clear
            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        bindSliderAciton()
        
        for i in 1...30 {
            devices.append("ID \(i)")
        }
        pageControl.numberOfPages = Int(ceil(Double(devices.count) / 9.0))
        pageControl.currentPage = 0
        
    }
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(2) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(3)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW)
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            let height = itemSize.height * 3.0 + flowLayout.minimumLineSpacing * 2.0 + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
            make.height.equalTo(height)
        }
        
        
        if devices.isEmpty {
            collectionView.showEmptyDataView(title: "No Members!", position: .center, bottomMargin: 3.5)
        }else {
            collectionView.hideEmptyDataView()
        }
        
    }
    
    @objc private func close() {
        dismiss(animated: true)
    }
    
    @objc private func moreClick() {
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                self?.editGroup()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
//                self?.deleteSite()
                self?.deleteGroup()
            }),
            .init(icon: UIImage(named: "menu_members"), title: "members".localizedString, tapItemBack: {[weak self] item in
                self?.members()
            }),
            .init(icon: UIImage(named: "menu_profile"), title: "profile".localizedString, tapItemBack: {[weak self] item in
//                self?.deleteSite()
            })
            
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight) + 44))
        
    }
    
    @objc private func onoffBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
    }
    
    private func bindSliderAciton() {
        lightnessSlider.valueChangedCallback = {[weak self] (value, ended) in
            print("lightness: \(value)")
        }
        
        cctSlider.valueChangedCallback = {[weak self] (value, ended) in
            print("cct: \(value)")
        }
    }
    
    /// 编辑组
    private func editGroup() {
        
        let editVc = GroupAddViewController(space: space, group: group)
        editVc.doneCallback = {[weak self] group in
            self?.title = group.name
            self?.groupUpdateCallback?(group)
        }
        let navVc = NavigationViewController(rootViewController: editVc)
        present(navVc, animated: true)
    }
    
    /// 删除组
    private func deleteGroup() {
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, contentPadding: SCRXFrom(25), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            GroupServer.deleteGroup(group: self.group, progress: nil) {[weak self] _ in
                XWHUDManager.hide()
                guard let self = self else { return }
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self.groupDeleteCallback?(self.group)
                self.close()
                
            } failed: { _ in
                // 跳转到
            }
            
        })]).show()
        
    }
    
    /// 查看成员
    private func members() {
        
        let vc = GroupMembersViewController(space: space, group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }

    
    private func setupUI() {
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(14)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
//        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(GroupDeviceViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(SCRYFit(40) + (navigationController?.navigationBar.frame.maxY ?? 0))
            make.height.equalTo(SCRYFrom(340))
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
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }
        
        onoffBtn = UIButton(normalImageName: "group_off", selectedImageName: "group_on", target: self, action: #selector(onoffBtnClick))
        view.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(32))
            make.centerX.equalToSuperview()
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.5
        view.addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.right.equalTo(collectionView)
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(44))
            make.height.equalTo(SCRYFrom(76))
        }
        
        cctSlider = BuoySliderView(frame: .zero, functionType: .cct())
        lightnessSlider.slider.interval = 0.5
        view.addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightnessSlider)
            make.top.equalTo(lightnessSlider.snp.bottom).offset(SCRYFit(2))
        }
        
    }


}

extension GroupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return devices.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupDeviceViewCell
        cell.nameLabel.text = devices[indexPath.item]
        return cell
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//
//    }
    
}
