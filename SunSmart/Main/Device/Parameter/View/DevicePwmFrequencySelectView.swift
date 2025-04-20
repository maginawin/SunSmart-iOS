//
//  DevicePwmFrequencySelectView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/18.
//

import UIKit

class DevicePwmFrequencySelectView: UIView {

    typealias SelectCallBack = ((Int)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    private var selectFrequency: Int = 0
    private var selectCallback: SelectCallBack?
    
    lazy private var frequencys: [Int] = {
        var list: [Int] = []
        for index in 1...40 {
            list.append(index * 490)
        }
        return list
    }()
    
    init(selectFrequency: Int?, selectCallback: SelectCallBack?) {
        super.init(frame: UIScreen.main.bounds)
        self.selectCallback = selectCallback
        self.selectFrequency = selectFrequency ?? self.frequencys[0]
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        var itemW = (collectionView.width - flowLayout.minimumInteritemSpacing * 4) / 5.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        flowLayout.itemSize = CGSize(width: itemW, height: SCRYFrom(32))
        let row = Int(ceil(Float(frequencys.count) / 5.0))
        collectionView.snp.updateConstraints { make in
            make.height.equalTo(flowLayout.itemSize.height * CGFloat(row) + flowLayout.minimumLineSpacing * CGFloat(row - 1))
        }
    }
    
    func show() {
        
        UIApplication.shared.keyWindow().addSubview(self)
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        }
    }
    
    private func hide() {
//        UIView.animate(withDuration: 0.15) {
//            self.shadeView.alpha = 0
//            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
//        } completion: { _ in
//            self.removeFromSuperview()
//        }
        self.removeFromSuperview()
    }
    
    @objc private func shadeViewAction() {
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = Background_Color
        contentView.layer.cornerRadius = SCRYFrom(20)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.center.equalToSuperview()
//            make.left.equalTo(SCRXFrom(10))
//            make.right.equalTo(SCRXFrom(-9))
            make.width.equalTo(SCRXFrom(356))
//            make.height.equalTo(SCRYFrom(316))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 1
        flowLayout.minimumInteritemSpacing = 1
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = RGB(217, 217, 217)
        collectionView.register(DevicePwmFrequencyViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.layer.borderColor = RGB(217, 217, 217).cgColor
        collectionView.layer.borderWidth = 1
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(30))
            make.bottom.equalTo(SCRYFrom(-30))
            make.height.equalTo(SCRYFrom(252))
        }
    }
    
}

extension DevicePwmFrequencySelectView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return frequencys.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicePwmFrequencyViewCell
        let frequency = frequencys[indexPath.item]
        cell.titleLabel.text = "\(frequency)"
        
        if frequency == selectFrequency {
            cell.titleLabel.textColor = .white
            cell.backgroundColor = Bar_Color
        }else {
            cell.titleLabel.textColor = TextBlack_Color
            cell.backgroundColor = indexPath.item / 5 % 2 == 1 ? .white : RGB(235, 235, 235)
        }
        
        return cell
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        var itemW = (collectionView.width - flowLayout.minimumInteritemSpacing * 4) / 5.0
//        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
//        return CGSize(width: itemW, height: SCRYFrom(32))
//    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let frequency = frequencys[indexPath.item]
//        selectFrequency = frequency
//        collectionView.reloadData()
        
        selectCallback?(frequency)
        hide()
    }
    
}

class DevicePwmFrequencyViewCell: UICollectionViewCell {
    
    var titleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(1))
            make.right.equalTo(SCRXFrom(-1))
            make.centerY.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
