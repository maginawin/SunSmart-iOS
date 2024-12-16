//
//  SceneAddCustomView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit

protocol SceneAddCustomViewDelegate: AnyObject {
    
    /// 选择图标回调
    /// - Parameters:
    ///   - index: 图标索引
//    func view(_ view: SceneAddCustomView, didSelectImage index: Int)
    
    /// 编辑名称回调
    /// - Parameters:
    ///   - name: 名称
    func view(_ view: SceneAddCustomView, didNameEditChanged name: String) -> String?

    /// 点击创建回调
    func customViewDidCreateAction(_ view: SceneAddCustomView)
    
}

class SceneAddCustomView: UIView {

    var titleLabel: UILabel!
    var nameField: UITextField!
    private var tipTextLabel: UILabel!
    private var flowLayout: UICollectionViewFlowLayout!
    var collectionView: UICollectionView!
    private var bottomView: UIView!
    private var bottomLineView: UIView!
    var createBtn: UIButton!
    
    private var imageNames: [String] = []
    
    weak var delegate: SceneAddCustomViewDelegate?
    
    var selectImageIndex: Int = 0
    
    init(frame: CGRect, name: String? = nil, imageNames: [String]) {
        super.init(frame: frame)
        setupUI()
        
        nameField.text = name
        self.imageNames = imageNames
    }
   
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func createBtnClick() {
        
        delegate?.customViewDidCreateAction(self)
    }
    
    @objc private func nameFieldEditChanged(sender: UITextField) {
        guard let text = sender.text else {
            return
        }
        let tipText = delegate?.view(self, didNameEditChanged: text)
        tipTextLabel.text = tipText
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "name".localizedString, textColor: Title_Color, fontSize: 15)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalToSuperview()
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = FONTS(15)
        nameField.layer.cornerRadius = 5
        nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        nameField.layer.borderWidth = 1
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
        nameField.leftViewMode = .always
        nameField.clearButtonMode = .always
        nameField.rightViewMode = .always
        nameField.backgroundColor = .white
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 13, fontWeight: .light)
        addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(2))
            make.right.equalTo(SCRXFrom(-24))
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color
        bottomView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        createBtn = UIButton(title: "CREATE".localizedString, titleSize: 16, titleColor: Title_Color, target: self, action: #selector(createBtnClick))
        createBtn.setTitleColor(RGB(156, 163, 175), for: .disabled)
        bottomView.addSubview(createBtn)
        createBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(20), bottom: SCRXFrom(16), right: SCRXFrom(20))
        collectionView.backgroundColor = .clear
        collectionView.register(GroupImageViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(26))
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }
    
}

extension SceneAddCustomView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageNames.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupImageViewCell
//        let source = imageNames[indexPath.item]
        cell.imageView.isHidden = false
        cell.imageView.image = UIImage(named: imageNames[indexPath.item])
        cell.nameLabel.isHidden = true
        cell.layer.borderWidth = selectImageIndex == indexPath.item ? 0.5 : 0
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        if let lastCell = collectionView.cellForItem(at: IndexPath(item: selectImageIndex, section: 0)) {
            lastCell.layer.borderWidth = 0
        }
        
        if let currentCell = collectionView.cellForItem(at: indexPath) {
            currentCell.layer.borderWidth = 0.6
        }
        selectImageIndex = indexPath.item
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(3) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(4)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        endEditing(true)
    }
    
}

extension SceneAddCustomView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
}
