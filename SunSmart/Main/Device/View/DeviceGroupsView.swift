//
//  DeviceGroupsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/12.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceGroupsViewDelegate: AnyObject {
    
    /// 选中/取消选中回调
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData)
}

class DeviceGroupsView: UIView {
    
    private var bgView: UIView!
    var flowLayout: HorizontalDirectionFlowLayout!
    
    var collectionView: UICollectionView!
    
    var progressView: LinePageControl!
    
    weak var delegate: DeviceGroupsViewDelegate?
    
    var datas: [DeviceGroupsSelectData] = [] {
        didSet {

            collectionView.snp.updateConstraints { make in
                if datas.count >= 4 {
                    make.bottom.equalToSuperview()
                    make.height.equalTo(SCRYFrom(108))
                }else {
                    make.bottom.equalToSuperview().offset(SCRYFrom(-6))
                    make.height.equalTo(SCRYFrom(58))
                }
            }
            progressView.numberOfPages = Int(ceil(Double(datas.count + 1) / 8.0))
            collectionView.reloadData()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
//        backgroundColor = .white
        setupUI()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
//        layer.shadowOffset = CGSizeMake(0, -2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 6
        layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: width, height: SCRYFrom(11))).cgPath
        
        bgView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10), rect: CGRect(x: 0, y: 0, width: width, height: height))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        flowLayout = HorizontalDirectionFlowLayout()
        flowLayout.itemRowCount = 2
        flowLayout.itmeColCount = 4
        flowLayout.minimumLineSpacing = SCRXFrom(8)
        flowLayout.minimumInteritemSpacing = SCRXFrom(8)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(12), left: 0, bottom: SCRYFrom(6), right: 0)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.bounces = false
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(4), bottom: 0, right: SCRXFrom(4))
        collectionView.register(DeviceGroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalToSuperview().offset(SCRYFrom(-6))
//            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(58))
//            make.height.equalTo(SCRYFrom(108))
        }
        
        progressView = LinePageControl()
        progressView.trackColor = RGB(238, 238, 239)
        progressView.progressColor = Bar_Color
        progressView.hidesForSinglePage = true
        progressView.numberOfPages = 1
        addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.width.equalTo(SCRXFrom(24))
            make.height.equalTo(SCRYFrom(4))
        }
    }
}

extension DeviceGroupsView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return datas.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DeviceGroupsViewCell
//        cell.isSelected = true
        let data = datas[indexPath.item]
        cell.titleLabel.text = data.name
        cell.isSelect = data.isSelected
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * 3.0) / 4.0
        itemW = CGFloat(floorf(Float(itemW) * 100.0) / 100.0)
        return CGSize(width: itemW, height: SCRYFrom(40))
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
       
        let data = datas[indexPath.item]
        data.isSelected = !data.isSelected
        delegate?.view(self, didSelectData: data)
        
        if let cell = collectionView.cellForItem(at: indexPath) as? DeviceGroupsViewCell {
            cell.isSelect = data.isSelected
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        progressView.setCurrentPage(page, animated: true)
    }
    
}


class DeviceGroupsViewCell: UICollectionViewCell {
    
    var titleLabel: UILabel!
    
    var isSelect: Bool = false {
        didSet {
            if isSelect {
                titleLabel.textColor = .white
                backgroundColor = Bar_Color
            }else {
                titleLabel.textColor =  RGB(46, 49, 93)
                backgroundColor = RGB(238, 238, 239)
            }
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(6)
        backgroundColor = RGB(238, 238, 239)
        
        titleLabel = UILabel(text: "ALL".localizedString, textColor: RGB(46, 49, 93), fontSize: 16, fontWeight: .light)
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

}
