//
//  SiteEditViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

class SiteEditViewController: UIViewController {

    private var headerView: UIView!
    private var nameLabel: UILabel!
    private var nameField: UITextField!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var footerView: UIView!
    private var doneBtn: UIButton!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    
    let site: SiteData
    
    init(site: SiteData) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = site.name
        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    @objc private func cancelBtnClick() {
        
        
    }
    
    @objc private func doneBtnClick() {
        
    }
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(100))
        }
        
        nameLabel = UILabel(text: "name".localizedString, textColor: TextBlack_Color, fontSize: 15)
        headerView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }
        
        nameField = UITextField()
        nameField.text = site.name
        nameField.textColor = TextBlack_Color
        nameField.font = FONTS(15)
        nameField.layer.cornerRadius = 5
        nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        nameField.layer.borderWidth = 1
        nameField.clearButtonMode = .whileEditing
        nameField.rightViewMode = .whileEditing
        nameField.backgroundColor = .white
        headerView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        footerView = UIView()
        footerView.backgroundColor = .white
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        lineView = UIView()
        lineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnClick))
        footerView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-60))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(30))
        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(doneBtnClick))
        footerView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.left).offset(SCRXFrom(60))
            make.centerY.height.equalTo(cancelBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: flowLayout.minimumLineSpacing, right: 0)
//        collectionView.dataSource = self
//        collectionView.delegate = self
//        collectionView.register(<#T##cellClass: AnyClass?##AnyClass?#>, forCellWithReuseIdentifier: <#T##String#>)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalTo(nameField)
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(footerView.snp.top)
        }
        
        
        
    }
    
}
