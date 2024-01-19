//
//  SceneAddDataListViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/21.
//

import UIKit
import NordicSigMeshSDK

protocol SceneAddDataListViewCellDelegate: AnyObject {
    
    /// 选择数据回调
    func cell(_ cell: SceneAddDataListViewCell, didSelectData index: Int)
    
    /// 长按编辑数据回调
    func cell(_ cell: SceneAddDataListViewCell, didLongPressData index: Int)
    
    /// 新增数据回调
    func cellDidAddAction(_ cell: SceneAddDataListViewCell)
}

class SceneAddDataListViewCell: UICollectionViewCell {
    
    var collectionView: UICollectionView!
    var flowLayout: UICollectionViewFlowLayout!
    
    var selectIndex: Int?
    /// 最大数量
    var maxCount = 16
    
    weak var delegate: SceneAddDataListViewCellDelegate?
    
    var sceneDatas: [SceneExecuteData]! {
        didSet {
            collectionView.reloadData()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func collectionViewDidLongPressAction(sender: UIGestureRecognizer) {
        let point = sender.location(in: collectionView)
        if sender.state == .began, let index = collectionView.indexPathForItem(at: point)?.item {
            delegate?.cell(self, didLongPressData: index)
        }
    }
    
    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(14), left: SCRXFrom(12), bottom: SCRYFrom(14), right: SCRXFrom(12))
        collectionView.backgroundColor = .clear
        collectionView.register(SceneAddDataViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(SceneAddDataAddCell.classForCoder(), forCellWithReuseIdentifier: "addCell")
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionViewDidLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        collectionView.isScrollEnabled = false
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.greaterThanOrEqualTo(SCRYFrom(96))
        }
    }
    
    
    
}

extension SceneAddDataListViewCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sceneDatas.count < maxCount ? sceneDatas.count + 1 : maxCount
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if indexPath.row == sceneDatas.count { // add
            let addCell = collectionView.dequeueReusableCell(withReuseIdentifier: "addCell", for: indexPath)
            return addCell
        }else { // data
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SceneAddDataViewCell
            cell.sceneData = sceneDatas[indexPath.item]
            cell.layer.borderColor = selectIndex == indexPath.item ? Bar_Color.cgColor : RGB(220, 220, 220).cgColor
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(3) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(4)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.row == sceneDatas.count { // add
            delegate?.cellDidAddAction(self)
        }else {
            delegate?.cell(self, didSelectData: indexPath.item)
        }
    }
    
}

class SceneAddDataViewCell: UICollectionViewCell {
    
    var offLabel: UILabel!
    var lightnessLabel: UILabel!
    var cctLabel: UILabel!
    
    var sceneData: SceneExecuteData! {
        didSet {
            
            if sceneData.lightness > 0 {
                offLabel.isHidden = true
                lightnessLabel.isHidden = false
                lightnessLabel.text = "\(sceneData.lightness)%"
                cctLabel.isHidden = false
                cctLabel.text = "\(sceneData.cct)K"
//                1900 + 2700
                let temperature100 = Node.getTemperature100(temperature: UInt16(sceneData.cct), range: SceneExecuteData.cctRange)
                let color = Node.getCctMixColor(temperature100: Int(temperature100))
                backgroundColor = color
                
            }else {
                offLabel.isHidden = false
                lightnessLabel.isHidden = true
                cctLabel.isHidden = true
                backgroundColor = RGB(226, 226, 226)
            }
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderWidth = 0.5
        layer.borderColor = Bar_Color.cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = height * 0.5
    }
    
    private func setupUI() {
        
        offLabel = UILabel(text: "off".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        offLabel.isHidden = true
        contentView.addSubview(offLabel)
        offLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        lightnessLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(lightnessLabel)
        lightnessLabel.snp.makeConstraints { make in
            make.bottom.equalTo(self.snp.centerY)
            make.centerX.equalToSuperview()
        }
        
        cctLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(cctLabel)
        cctLabel.snp.makeConstraints { make in
            make.top.equalTo(self.snp.centerY)
            make.centerX.equalToSuperview()
        }
        
    }
    
}

class SceneAddDataAddCell: UICollectionViewCell {
    
    private var addImageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderColor = RGB(220, 220, 220).cgColor
        layer.borderWidth = 0.5
        backgroundColor = .white
        
        addImageView = UIImageView(image: UIImage(named: "scene_data_add"))
        contentView.addSubview(addImageView)
        addImageView.snp.makeConstraints { make in
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
