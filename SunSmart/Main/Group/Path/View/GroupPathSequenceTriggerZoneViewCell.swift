//
//  GroupPathSequenceTriggerZoneViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/21.
//

import UIKit
import NordicSigMeshSDK

protocol GroupPathSequenceTriggerZoneViewCellDelegate: AnyObject {
    
    /// 识别设备
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, deviceIdentify device: Node)
    
    /// 删除设备
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, removeDevice device: Node)
    
    /// 点击选择zone
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, didSelectZone zone: GroupProximityLightingPathZone)
    
    /// 添加设备 address：关联的设备地址
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, addDevice address: Address)
}


class GroupPathSequenceTriggerZoneViewCell: UITableViewCell {

    private var noDataLabel: UILabel!
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    private let colCount: Int = 5
    
    var zone: GroupProximityLightingPathZone!
    private var zoneIndex: Int = 0
    
    var isSelect: Bool = false {
        didSet {
            collectionView.layer.borderWidth = isSelect ? 1 : 0
        }
    }
    
    weak var delegate: GroupPathSequenceTriggerZoneViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        setupUI()
        
        addInteraction(UIDropInteraction(delegate: self))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if collectionView.frame != .zero {
            var itemW = ((collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right) - CGFloat(colCount - 1) * flowLayout.minimumInteritemSpacing) / CGFloat(colCount)
            itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
            flowLayout.itemSize = CGSize(width: itemW, height: itemW)
        }
        
    }
    
//    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
//        let touchView = super.hitTest(point, with: event)
//        if !self.isSelect, touchView == self.collectionView, self.collectionView.indexPathForItem(at: point) == nil {
//            delegate?.cell(self, didSelectZone: zone)
//        }
//        return touchView
//    }
    @objc private func collectionViewDidTapAction(sender: UIGestureRecognizer) {
        if !isSelect {
            delegate?.cell(self, didSelectZone: zone)
        }
    }
    
    /// 刷新数据
    func reloadData(zoneIndex: Int, zone: GroupProximityLightingPathZone) {
        self.zoneIndex = zoneIndex
        self.zone = zone
        
        noDataLabel.isHidden = zone.nodes.count > 0
        
        let row = ceil(Double(zone.nodes.count) / Double(colCount))
        collectionView.snp.updateConstraints { make in
            make.height.equalTo(max(row * flowLayout.itemSize.height + (row - 1) * flowLayout.minimumLineSpacing + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom, SCRYFrom(60)))
        }
        collectionView.reloadData() 
    }
    
    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = SCRXFrom(18)
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: SCRYFrom(16), right: 0)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(17), bottom: 0, right: SCRXFrom(18))
        collectionView.backgroundColor = .white
        collectionView.layer.cornerRadius = SCRYFrom(10)
        collectionView.layer.borderColor = Yellow_Color.cgColor
        collectionView.dataSource = self
        collectionView.delegate = self
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(collectionViewDidTapAction))
//        longPress.minimumPressDuration = 0.5
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
        collectionView.register(GroupPathSequencePathItem.classForCoder(), forCellWithReuseIdentifier: "cell")
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
        
        noDataLabel = UILabel(text: "No_Data".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        noDataLabel.isHidden = true
        contentView.addSubview(noDataLabel)
        noDataLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
}

extension GroupPathSequenceTriggerZoneViewCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return zone.nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupPathSequencePathItem
        let node = zone.nodes[indexPath.item]
        cell.sequenceLabel.isHidden = true
        cell.nameLabel.text = node.name
        if node.state {
            cell.nameLabel.textColor = SubText_Color
            cell.iconImageView.image = UIImage(named: "path_device")
        }else {
            cell.nameLabel.textColor = AssistText_Color
            cell.iconImageView.image = UIImage(named: "path_device_offline")
        }
        return cell
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        var itemW = ((collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right) - CGFloat(colCount - 1) * flowLayout.minimumInteritemSpacing) / CGFloat(colCount)
//        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
//        return CGSize(width: itemW, height: itemW)
//    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? GroupPathSequencePathItem else {
            return
        }
        
        cell.boxView.layer.borderColor = Yellow_Color.cgColor
        
        let menuWidth = SCRXFrom(71)
        let options: [PathItemOptions] = [.identify, .remove]
        
        var point = CGPoint(x: cell.frame.minX, y: cell.frame.maxY + SCRYFrom(8))
        if point.x + menuWidth > collectionView.frame.maxX {
            point.x -= (menuWidth - cell.width) * 0.5
        }
        let anchorPoint = collectionView.convert(point, to: UIApplication.shared.keyWindow())
        
        TitleSelectView.show(titles: options.map({ $0.name }), style: .default, anchorPoint: anchorPoint, menuWidth: menuWidth, itemHeight: SCRYFrom(30), titleFont: UIFont.systemFont(ofSize: 13, weight: .light)) {[weak self] index in
            guard let self = self else { return }
            print(options[index].name)
            let type = options[index]
            switch type {
            case .identify:
                self.delegate?.cell(self, deviceIdentify: self.zone.nodes[indexPath.item])
            case .remove:
                self.delegate?.cell(self, removeDevice: self.zone.nodes[indexPath.item])
            default:
                break
            }
        } hideCallback: {
            cell.boxView.layer.borderColor = RGB(241, 242, 244).cgColor
        }
        
    }
    
}

extension GroupPathSequenceTriggerZoneViewCell: UIDropInteractionDelegate {
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSString.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: NSString.self) {[weak self] items in
            guard let self = self, self.isSelect else { return }
            
            guard let addressHex = items.first as? String, let address = Address(hex: addressHex) else { return }
            self.delegate?.cell(self, addDevice: address)
        }
    }
    
}
