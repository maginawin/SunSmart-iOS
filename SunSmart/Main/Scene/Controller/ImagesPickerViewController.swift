//
//  ImagesPickerViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit

class ImagesPickerViewController: UIViewController {

    typealias PickerCallback = ((Int)->Void)
    
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var bottomView: UIView!
    private var doneBtn: UIButton!
    
    private var selectImageIndex: Int = 0
    private let imageNames: [String]
    
    var pickerCallback: PickerCallback?
    
    init(title: String? = nil, imageNames: [String], selectIndex: Int = 0, callback: PickerCallback?) {
        self.imageNames = imageNames
        self.selectImageIndex = selectIndex
        self.pickerCallback = callback
        super.init(nibName: nil, bundle: nil)
        
        self.title = title ?? "select_icon".localizedString
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        if presentationController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
            navigationController?.setNavigationBarBackgroundColor(color: .clear)
        }
        
        setupUI()
    }

    @objc private func close() {
        
        dismiss(animated: true)
    }
    
    @objc private func doneBtnAction() {
        close()
        pickerCallback?(selectImageIndex)
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnAction))
        bottomView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(24), left: SCRXFrom(20), bottom: SCRXFrom(16), right: SCRXFrom(20))
        collectionView.backgroundColor = .clear
        collectionView.register(ImagePickerViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }
    
}

extension ImagesPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageNames.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ImagePickerViewCell
//        let source = imageNames[indexPath.item]
        cell.imageView.image = UIImage(named: imageNames[indexPath.item])
        cell.layer.borderWidth = selectImageIndex == indexPath.item ? 0.5 : 0
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard selectImageIndex != indexPath.item else {
            return
        }
        
        if let lastCell = collectionView.cellForItem(at: IndexPath(item: selectImageIndex, section: 0)) {
            lastCell.layer.borderWidth = 0
        }
        
        if let currentCell = collectionView.cellForItem(at: indexPath) {
            currentCell.layer.borderWidth = 0.5
        }
        selectImageIndex = indexPath.item
        
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(3) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(4)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
}


class ImagePickerViewCell: UICollectionViewCell {
    
    var imageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        layer.borderColor = Bar_Color.cgColor
        layer.borderWidth = 0
        clipsToBounds = true
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = height * 0.5
    }
    
}
