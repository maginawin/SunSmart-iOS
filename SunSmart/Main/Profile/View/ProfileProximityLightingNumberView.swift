//
//  ProfileProximityLightingNumberView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit

protocol ProfileProximityLightingNumberViewDelegate: AnyObject {
    
    /// 邻近照明数量修改
    /// - Parameters:
    ///   - view: view
    ///   - number: 数量 0-5 | 255
    func view(_ view: ProfileProximityLightingNumberView, lightingNumberChanged number: UInt8)
    
    /// 禁止交互下编辑事件
    func proximityLightingNumberViewDisableEditAction(view: ProfileProximityLightingNumberView)
    
}

class ProfileProximityLightingNumberView: UIView {

    /// 数量类型
    enum ItemNumberType {
        /// 数量0-5 | 6：max
        case number(_ number: UInt8)
        /// 更多...
        case more
    }
    
    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var contentView: UIView!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var personImageView: UIImageView!
    private var numberTitleLabel: UILabel!
    /// 滑条
    var numberSlider: PowerUpLightSliderView!
    
    weak var delegate: ProfileProximityLightingNumberViewDelegate?
    
    private var numberTypes: [ItemNumberType] = [
        .number(6), .more, .number(5), .number(4), .number(3), .number(2), .number(1), .number(0), .number(1), .number(2), .number(3), .number(4), .number(5), .more, .number(6)
    ]
    
    private let numberRanage: ClosedRange<UInt8> = 0...5
    
    var number: UInt8 = 2 {
        didSet {
            if number == .max {
                numberSlider.slider.value = numberSlider.slider.maximumValue
                numberSlider.valueLabel.text = "ALL".localizedString
            }else {
                numberSlider.slider.value = Float(number)
                numberSlider.valueLabel.text = "\(number)"
            }
            collectionView.reloadData()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if collectionView.frame == .zero {
            collectionView.layoutIfNeeded()
        }
        
        var spacing = (collectionView.width - flowLayout.itemSize.width * CGFloat(numberTypes.count)) / CGFloat(numberTypes.count - 1)
        spacing = CGFloat(floorf(Float(spacing) * 100) / 100.0)
        flowLayout.minimumInteritemSpacing = spacing
        
    }
    
    @objc private func helpBtnAction() {
        
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "number_of_neighbour_node".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "profile_help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalTo(titleLabel)
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(7)
        contentView.backgroundColor = Background_Color
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(11))
            make.height.equalTo(SCRYFrom(96))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.itemSize = CGSize(width: SCRXFrom(12), height: SCRYFrom(36))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.register(ProfileProximityLightingNumberViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(21))
            make.right.equalTo(SCRXFrom(-21))
            make.top.equalTo(SCRYFrom(14))
            make.height.equalTo(SCRYFrom(36))
        }
        
        personImageView = UIImageView(image: UIImage(named: "profile_person"))
        contentView.addSubview(personImageView)
        personImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-14))
        }
        
        numberTitleLabel = UILabel(text: "number".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(numberTitleLabel)
        numberTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(contentView.snp.bottom).offset(SCRYFrom(13))
        }
        
        numberSlider = PowerUpLightSliderView()
        numberSlider.slider.minimumValue = 0
        numberSlider.slider.maximumValue = 6
        numberSlider.slider.value = min(Float(number), numberSlider.slider.maximumValue)
        numberSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            if value == Int(self.numberSlider.slider.maximumValue) {
                self.numberSlider.valueLabel.text = "ALL".localizedString
                self.delegate?.view(self, lightingNumberChanged: UInt8.max)
            }else {
                self.numberSlider.valueLabel.text = "\(value)"
                self.delegate?.view(self, lightingNumberChanged: UInt8(value))
            }
            self.collectionView.reloadData()
            
        }
        numberSlider.disableEditActionCallback = {[weak self] in
            guard let self = self else { return }
            self.delegate?.proximityLightingNumberViewDisableEditAction(view: self)
        }
        addSubview(numberSlider)
        numberSlider.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
//            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(SCRYFrom(76))
        }
        
    }
    
}

extension ProfileProximityLightingNumberView: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return numberTypes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ProfileProximityLightingNumberViewCell
        let type = numberTypes[indexPath.item]
        switch type {
        case .more:
            cell.numberLabel.isHidden = true
            cell.indicateView.isHidden = true
            cell.moreLabel.isHidden = false
        case .number(let number):
            cell.numberLabel.isHidden = false
            if !numberRanage.contains(number) {
                cell.numberLabel.text = "N"
            }else {
                cell.numberLabel.text = "\(number)"
            }
            cell.indicateView.isHidden = false
            cell.indicateView.backgroundColor = UInt8(numberSlider.slider.value) >= number ? Yellow_Color : RGB(217, 217, 217)
            cell.moreLabel.isHidden = true
            
        }
        return cell
    }
    
}

class ProfileProximityLightingNumberViewCell: UICollectionViewCell {
    
    var numberLabel: UILabel!
    var indicateView: UIView!
    var moreLabel: UILabel!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        numberLabel = UILabel(text: "0", textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(numberLabel)
        numberLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        indicateView = UIView()
        indicateView.layer.cornerRadius = SCRYFrom(4)
        indicateView.backgroundColor = RGB(217, 217, 217)
        contentView.addSubview(indicateView)
        indicateView.snp.makeConstraints { make in
            make.bottom.centerX.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(8))
        }
        
        moreLabel = UILabel(text: "...", textColor: AssistText_Color, fontSize: 12, fit: false)
        moreLabel.isHidden = true
        contentView.addSubview(moreLabel)
        moreLabel.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-1))
            make.centerX.equalToSuperview()
        }
    }
    
}
