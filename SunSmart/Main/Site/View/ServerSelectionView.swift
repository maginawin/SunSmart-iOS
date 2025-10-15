//
//  ServerSelectionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/6.
//

import UIKit

class ServerSelectionView: UIView {

    typealias ServerSelectionCallback = ((ServerRegion)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var lineView: UIView!
    private var okBtn: UIButton!
    private var regions: [ServerRegion] = ServerRegion.defaultRegions
    private var selectRegion: ServerRegion = .asiaPacific
    
    private var selectionCallback: ServerSelectionCallback?
    
    init(selectRegion: ServerRegion = .asiaPacific, selectionCallback: ServerSelectionCallback?) {
        
        super.init(frame: UIScreen.main.bounds)
        self.selectionCallback = selectionCallback
        self.selectRegion = selectRegion
        setupUI()
    }
    
    func show() {
        if superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        layoutIfNeeded()
        contentView.y = self.height
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = (self.height - self.contentView.height) * 0.5
            self.shadeView.alpha = 1
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height
            self.shadeView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func okBtnAction() {
        selectionCallback?(self.selectRegion)
        hide()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let itemW = contentView.width - collectionView.contentInset.left - collectionView.contentInset.right
        flowLayout.itemSize = CGSize(width: CGFloat(floor(itemW)), height: SCRYFrom(56))
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(20)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-15))
            make.height.equalTo(self.contentView.snp.width).multipliedBy(378 / 344.0)
        }
        
        titleLabel = UILabel(text: "server_selection".localizedString, textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        messageLabel = UILabel(text: "server_selection_message".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(0, 0, 0, 0.03)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
            make.bottom.equalTo(SCRYFrom(-59))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        flowLayout.minimumInteritemSpacing = 0
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(20), bottom: 0, right: SCRXFrom(20))
        collectionView.register(ServerSelectionViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = .white
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(20))
//            make.right.equalTo(SCRXFrom(-20))
            make.left.right.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(20))
            make.bottom.equalTo(lineView.snp.top)
        }
        
        okBtn = UIButton(title: "ok".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(okBtnAction))
        contentView.addSubview(okBtn)
        okBtn.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(lineView.snp.bottom)
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension ServerSelectionView: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return regions.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ServerSelectionViewCell
        let region = regions[indexPath.item]
        cell.iconImageView.image = UIImage(named: region.data.icon)
        cell.nameLabel.text = region.data.name
        cell.nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.selectedImageView.isHidden = region != selectRegion
        cell.layer.cornerRadius = 0
        cell.backgroundColor = .clear
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let region = regions[indexPath.item]
        self.selectRegion = region
        collectionView.reloadData()
    }
    
}
