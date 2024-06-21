//
//  InfoEditViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

class InfoEditViewController: UIViewController {

    private var headerView: UIView!
    private var nameLabel: UILabel!
    private var nameField: UITextField!
    private var tipTextLabel: UILabel!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var footerView: UIView!
    private var doneBtn: UIButton!
//    private var cancelBtn: UIButton!
    private var lineView: UIView!
    
    private let name: String
    private let imageNames: [String]
    private let columnNum: Int
    private var selectImageIndex: Int
    /// 是否重名
    private var isTautonym: Bool = false
    /// 最大输入文本
    private var maxInputLength = 32
    private let isAdd: Bool
    
//    var radius: CGFloat = SCRXFrom(8)
    /// item是否圆型展示
    var itemRound: Bool = false
    
    
    /// 名称编辑回调（当前输入名称->是否重名）
    var nameEditChangedCallback: ((String)->(Bool))?
    
    /// 完成回调（名称、图片index）reutrn 是否退出
    var doneCallback: ((String, Int)->Bool)?
    
    init(name: String, imageNames: [String], selectImageIndex: Int, columnNum: Int = 4, isAdd: Bool = false) {
        self.name = name
        self.imageNames = imageNames
        self.columnNum = columnNum
        self.selectImageIndex = selectImageIndex
        self.isAdd = isAdd
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if title == nil {
            title = name
        }
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
//        navigationController?.navigationBar.layer.cornerRadius = 20
//        navigationController?.navigationBar.layer.masksToBounds = true
        
        if presentationController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        setupUI()
        if isAdd {
            doneBtn.setTitle("add".localizedString, for: .normal)
        }
        nameField.text = name
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
    }
    
    @objc private func close() {
        if presentationController != nil {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func cancelBtnClick() {
        close()
    }
    
    @objc private func doneBtnClick() {
        
        guard let text = nameField.text else {
            return
        }
        
        // 重名/未输入
        if isTautonym || text.isAllInputTextEmpty(){
            return
        }
        if doneCallback?(text, selectImageIndex) ?? true {
            close()
        }
    }
    
    @objc private func nameFieldEditChanged(sender: UITextField) {
        guard let text = sender.text else {
            return
        }
        if text.count > maxInputLength { // 是否超限
            sender.text = text.subString(rang: NSMakeRange(0, maxInputLength))
            tipTextLabel.text = "text_length_exceeded".localizedString
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
            self.perform(#selector(textExceededHide), with: nil, afterDelay: 2)
        }else {
            // 是否重名
            if let result = nameEditChangedCallback?(text) {
                tipTextLabel.text = result ? "name_already_exists".localizedString : nil
                self.isTautonym = result
                if result {
                    doneBtn.isEnabled = false
                }else {
                    doneBtn.isEnabled = true
                }
            }else {
                doneBtn.isEnabled = true
            }
            if text.isEmpty {
                doneBtn.isEnabled = false
            }
        }
        
       
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }
    
    @objc private func textExceededHide() {
        nameFieldEditChanged(sender: nameField)
    }
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.height.equalTo(SCRYFrom(111))
        }
        
        nameLabel = UILabel(text: "name".localizedString, textColor: TextBlack_Color, fontSize: 15)
        headerView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = FONTS(15)
        nameField.layer.cornerRadius = 5
        nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        nameField.layer.borderWidth = 1
        nameField.clearButtonMode = .whileEditing
        nameField.rightViewMode = .whileEditing
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
        nameField.leftViewMode = .always
        nameField.returnKeyType = .done
        nameField.backgroundColor = .white
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        headerView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
        headerView.addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(2))
            make.right.equalTo(SCRXFrom(-24))
        }
        
        footerView = UIView()
        footerView.backgroundColor = .white
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243)
        footerView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
//            make.height.equalTo(SCRYFrom(40))
        }
        
//        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnClick))
//        cancelBtn.titleLabel?.textAlignment = .center
//        footerView.addSubview(cancelBtn)
//        cancelBtn.snp.makeConstraints { make in
//            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-33))
//            make.centerY.equalTo(lineView)
//            make.width.equalTo(SCRXFrom(120))
//            make.height.equalTo(SCRYFrom(30))
//        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnClick))
        doneBtn.setTitleColor(RGB(139, 139, 139), for: .disabled)
        doneBtn.titleLabel?.textAlignment = .center
        footerView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
//            make.left.equalTo(lineView.snp.left).offset(SCRXFrom(33))
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
//            make.centerY.height.width.equalTo(cancelBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: flowLayout.minimumLineSpacing, right: 0)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ImageCollectionViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalTo(nameField)
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
        }
        
        
        
    }

}

extension InfoEditViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageNames.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ImageCollectionViewCell
        cell.imageView.image = UIImage(named: imageNames[indexPath.item])
        cell.layer.borderWidth = selectImageIndex == indexPath.item ? 1 : 0
        if itemRound {
            cell.layer.cornerRadius = cell.height * 0.5
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard selectImageIndex != indexPath.item else {
            return
        }
        var reloadIndexPaths: [IndexPath] = []
        reloadIndexPaths.append(IndexPath(item: selectImageIndex, section: 0))
        reloadIndexPaths.append(indexPath)
        selectImageIndex = indexPath.item
        
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: reloadIndexPaths)
        CATransaction.commit()
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - flowLayout.minimumInteritemSpacing * CGFloat(columnNum - 1)) / CGFloat(columnNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
    
}


extension InfoEditViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    
//    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//
//        // 计算的实际文本
//        let realText = (textField.text ?? "") + string
//        if realText.count > maxInputLength && !string.isEmpty {
//            tipTextLabel.text = "text_length_exceeded".localizedString
//            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
//            self.perform(#selector(textExceededHide), with: nil, afterDelay: 2)
//            return false
//        }
//        
//        return true
//    }
    
}
