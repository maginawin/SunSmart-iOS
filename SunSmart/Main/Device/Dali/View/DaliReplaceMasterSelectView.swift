//
//  DaliReplaceMasterSelectView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/3.
//

import UIKit
import NordicSigMeshSDK

class DaliReplaceMasterSelectView: UIView {

    typealias SelectMasterCallback = ((Node)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var topBarView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var bottomView: UIView!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    private var confirmBtn: UIButton!
    
    private var selectMaster: Node?
    
    let nodes: [Node]
    private var selectCallback: SelectMasterCallback?
    
    init(frame: CGRect = UIScreen.main.bounds, selectMaster: Node? = nil, nodes: [Node], selectCallback: SelectMasterCallback?) {
        self.nodes = nodes
        super.init(frame: frame)
        self.selectMaster = selectMaster
        self.selectCallback = selectCallback
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
            layoutIfNeeded()
            if nodes.isEmpty {
                showEmptyUI()
            }
        }
        self.shadeView.alpha = 0
        self.contentView.y = height
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
        }
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    private func showEmptyUI() {
        
        collectionView.showEmptyDataView(title: "no_scenes".localizedString, tipText: "no_scenes_message".localizedString, position: .center, bottomMargin: SCRYFit(45))
    }

    /// 取消
    @objc private func cancelBtnAction() {
        hide()
    }
    
    /// 确认
    @objc private func confirmBtnAction() {
        hide()
        if let selectMaster = self.selectMaster {
            selectCallback?(selectMaster)
        }
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelBtnAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(SCRYFrom(24) + kNavigationHeight)
        }
        
        topBarView = UIView()
        topBarView.backgroundColor = Background_Color
        topBarView.layer.cornerRadius = SCRYFrom(15)
        contentView.addSubview(topBarView)
        topBarView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(53))
        }
        
        titleLabel = UILabel(text: "list_of_replaceable_devices".localizedString, textColor: RGB(72, 72, 74), fontSize: 18)
        topBarView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        messageLabel = UILabel(text: nil, textColor: Message_Color, fontSize: 13, fit: false)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        messageLabel.attributedText = NSAttributedString(string: "dali_master_replaceable_devices_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        contentView.addSubview(messageLabel)
        
        
        bottomView = UIView()
        bottomView.backgroundColor = Background_Color
        bottomView.layer.cornerRadius = SCRYFrom(15)
        contentView.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-34)
            make.height.equalTo(SCRYFrom(60))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(216, 216, 216)
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(24))
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleWeight: .light, titleColor: RGB(72, 72, 74), target: self, action: #selector(cancelBtnAction))
        bottomView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(lineView.snp.left)
        }
        
        confirmBtn = UIButton(title: "confirm".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bottom_Done_Color, target: self, action: #selector(confirmBtnAction))
        bottomView.addSubview(confirmBtn)
        confirmBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right)
            make.top.bottom.right.equalToSuperview()
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = Background_Color
        collectionView.layer.cornerRadius = SCRYFrom(15)
        collectionView.alwaysBounceVertical = true
        collectionView.register(ScheduleGroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalTo(bottomView.snp.top).offset(SCRYFrom(-8))
        }
        
        
    }
    
    
}

extension DaliReplaceMasterSelectView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ScheduleGroupsViewCell
        let node = nodes[indexPath.item]
        cell.nameLabel.text = node.name
        cell.selectedImageView.image = UIImage(named: selectMaster == node ? "schedule_target_select" : "schedule_target_select_un")
        cell.onoffBtn.isHidden = false
        cell.onoffBtn.setImage(UIImage(named: "device_identify"), for: .normal)
        cell.onoffBtn.setImage(UIImage(named: "device_identify_disable"), for: .disabled)
        cell.onoffBtn.isEnabled = node.state
        cell.failedImageView.isHidden = true
        cell.onoffCallback = { _ in
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        return CGSize(width: CGFloat(floorf(Float(itemW) * 100) / 100), height: SCRYFrom(44))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = nodes[indexPath.item]
        selectMaster = node
        collectionView.reloadData()
    }
    
}
