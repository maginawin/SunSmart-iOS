//
//  DeviceGroupsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/12.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceGroupsViewDelegate: AnyObject {
    
    /// 选择/取消选择所有回调
    func view(_ view: DeviceGroupsView, didSelectAllAction selectAll: Bool)
    
    /// 选中/取消选中回调
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData)
    
    /// 筛选
    func viewDidSortAction(_ view: DeviceGroupsView)
}

class DeviceGroupsView: UIView {
    
    private var bgView: UIView!
    
    var selectAllBtn: UIButton!
    var sortBtn: UIButton!
    var selectCountLabel: UILabel!
    
    private var flowLayout: HorizontalDirectionFlowLayout!
    
    var collectionView: UICollectionView!
    
    var progressView: LinePageControl!
    
    var lineView: UIView!
    
    var itemSize: CGSize?
    
    weak var delegate: DeviceGroupsViewDelegate?
    
    var datas: [DeviceGroupsSelectData] = [] {
        didSet {

            collectionView.snp.updateConstraints { make in
//                let top = SCRYFrom(46)
                if datas.count > 0 {
                    make.bottom.equalToSuperview().offset(SCRYFrom(-6))
                    
                    let row = min(Int(ceil(CGFloat(datas.count) / 4.0)), 2)
                    var height = CGFloat(row) * (SCRYFrom(40) + SCRYFrom(8))
                    if datas.count > 8 {
                        height += SCRYFrom(6)
                    }
                    make.height.equalTo(height)
                }else {
                    make.bottom.equalToSuperview()
                    make.height.equalTo(SCRYFrom(8))
                }
            }
            progressView.numberOfPages = Int(ceil(Double(datas.count) / 8.0))
            flowLayout.itemColCount = datas.count > 4 ? 2 : 1
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
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
        delegate?.view(self, didSelectAllAction: !sender.isSelected)
    }
    
    @objc private func sortBtnAction() {
        delegate?.viewDidSortAction(self)
    }
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bgView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(8))
        }
        
        sortBtn = UIButton(normalImageName: "space_sort", target: self, action: #selector(sortBtnAction))
        bgView.addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        selectCountLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        selectCountLabel.isHidden = true
        bgView.addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        flowLayout = HorizontalDirectionFlowLayout()
        flowLayout.itemRowCount = 4
        flowLayout.itemColCount = 1
        flowLayout.minimumLineSpacing = SCRXFrom(8)
        flowLayout.minimumInteritemSpacing = SCRXFrom(8)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(4), bottom: 0, right: SCRXFrom(4))
        flowLayout.itemHeight = SCRYFrom(40)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.bounces = false
//        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(4), bottom: 0, right: SCRXFrom(4))
        collectionView.register(DeviceGroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.top.equalTo(SCRYFrom(46))
            make.height.equalTo(SCRYFrom(8))
        }
        
        progressView = LinePageControl()
        progressView.trackColor = RGB(238, 238, 239)
        progressView.progressColor = Bar_Color
        progressView.hidesForSinglePage = true
        progressView.numberOfPages = 1
        addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-8))
            make.width.equalTo(SCRXFrom(24))
            make.height.equalTo(SCRYFrom(4))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(1)
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
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        if let size = itemSize {
//            return size
//        }
//        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * 3.0) / 4.0
//        itemW = CGFloat(floorf(Float(itemW) * 100.0) / 100.0)
//        
//        return CGSize(width: itemW, height: SCRYFrom(40))
//    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
       
        let data = datas[indexPath.item]
        data.isSelected = !data.isSelected
        delegate?.view(self, didSelectData: data)
        
        if let cell = collectionView.cellForItem(at: indexPath) as? DeviceGroupsViewCell {
            cell.isSelect = data.isSelected
        }
//        selectAllBtn.isSelected = datas.count > 0 && datas.filter({ $0.isSelected }).count == datas.count
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
        
        titleLabel = UILabel(text: "ALL".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
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
