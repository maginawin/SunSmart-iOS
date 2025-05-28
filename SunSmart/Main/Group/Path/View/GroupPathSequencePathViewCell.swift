//
//  GroupPathSequencePathViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit
import NordicSigMeshSDK

protocol GroupPathSequencePathViewCellDelegate: AnyObject {
    
    /// 选择item路径方向
    /// - Parameters:
    ///   - cell: cell
    ///   - item: 选择的item
    ///   - itemIndex: item索引
    ///   - direction: 方向
    func cell(_ cell: GroupPathSequencePathViewCell, didSelectDirection item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem, direction: PathDirection)
    
    /// 添加item
    /// - Parameters:
    ///   - cell: cell
    ///   - count: 添加item数量
    ///   - insertIndex: 在哪个位置插入
    func cell(_ cell: GroupPathSequencePathViewCell, didAddItem count: Int, insertIndex: Int)
    
    /// 识别item内设备
    func cell(_ cell: GroupPathSequencePathViewCell, deviceIdentify item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem)
    
    /// 删除item内设备
    func cell(_ cell: GroupPathSequencePathViewCell, removeDevice item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem)
    
    /// 删除item
    func cell(_ cell: GroupPathSequencePathViewCell, deleteItem item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem)
    
    /// 设置item关联设备 address：关联的设备地址
    func cell(_ cell: GroupPathSequencePathViewCell, bindDevice item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem, address: Address)
    
}

/// 路径item操作选项
enum PathItemOptions {
    
    var name: String {
        switch self {
        case .overturn:
            return "overturn".localizedString
        case .startRight:
            return "start_right".localizedString
        case .startLeft:
            return "start_left".localizedString
        case .insertRight:
            return "insert_right".localizedString
        case .insertLeft:
            return "insert_left".localizedString
        case .identify:
            return "identify".localizedString
        case .remove:
            return "remove".localizedString
        case .delete:
            return "delete".localizedString
        }
    }
    
    /// 反转方向
    case overturn
    /// item往右添加设备
    case startRight
    /// item往左添加设备
    case startLeft
    /// 在item右边插入一个item
    case insertRight
    /// 在item左边插入一个item
    case insertLeft
    /// 识别
    case identify
    /// 删除设备
    case remove
    /// 删除item
    case delete
}


class GroupPathSequencePathViewCell: UITableViewCell {
    
    private var flowLayout: GroupPathSequencePathLayout!
    private var collectionView: UICollectionView!
    
    private let colCount: Int = 5
    
    var path: GroupProximityLightingSequencePath!
    private var pathIndex: Int = 0
    
    weak var delegate: GroupPathSequencePathViewCellDelegate?
    /// 选择的路径数据
    var selectPathData: GroupPathSequenceSelectData? {
        didSet {
            if selectPathData?.path == path {
                collectionView.layer.borderWidth = 1
            }else {
                collectionView.layer.borderWidth = 0
            }
            collectionView.reloadData()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        setupUI()
        
        addInteraction(UIDropInteraction(delegate: self))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 刷新数据
    func reloadData(pathIndex: Int, path: GroupProximityLightingSequencePath, reloadCollectionView: Bool = true) {
        self.pathIndex = pathIndex
        self.path = path
        let row = ceil(Double(path.items.count + 2) / Double(colCount))
        collectionView.snp.updateConstraints { make in
            make.height.equalTo(row * SCRYFrom(62) + (row - 1) * flowLayout.minimumLineSpacing + collectionView.contentInset.top + collectionView.contentInset.bottom)
        }
        if reloadCollectionView {
            collectionView.reloadData()
        }
    }
    
    private func setupUI() {
        
        flowLayout = GroupPathSequencePathLayout()
        flowLayout.minimumInteritemSpacing = SCRXFrom(18)
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(10), left: SCRXFrom(17), bottom: SCRYFrom(10), right: SCRXFrom(18))
        collectionView.backgroundColor = .white
        collectionView.layer.cornerRadius = SCRYFrom(10)
        collectionView.layer.borderColor = Yellow_Color.cgColor
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionViewLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        collectionView.register(GroupPathSequencePathItem.classForCoder(), forCellWithReuseIdentifier: "pathItem")
        collectionView.register(GroupPathSequencePathAddItem.classForCoder(), forCellWithReuseIdentifier: "addItem")
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(82))
        }
    }
    
    @objc private func collectionViewLongPressAction(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        if indexPath.row == 0 || indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1 { // Add
            if indexPath.row == 0 {
                addPoint(location: indexPath.row)
            }else {
                addPoint(location: indexPath.row - 1)
            }
        }
    }
    
    private func addPoint(location: Int) {
        
        let remainingPointCount = GroupProximityLightingSequencePath.maxPathItemCount - path.items.count
        guard remainingPointCount > 0 else {
            XWHUDManager.showTipHUD("not_points_remaining", isLineFeed: true)
            return
        }
        let range = 1...remainingPointCount
        
        SRAlertView(title: "add_point".localizedString, message: String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), messageColor: Message_Color, inputFieldStyle: .init(placeholder: String(format: "remaining_paths_number".localizedString, remainingPointCount), keyboardType: .numberPad, maxInputLength: 3, textAlignment: .center, showClear: true), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)], textValueChangedBack: nil) {[weak self] text in
            guard let self = self, let number = Int(text), range.contains(number) else {
                XWHUDManager.showTipHUD(String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), isLineFeed: true)
                return
            }
            self.delegate?.cell(self, didAddItem: number, insertIndex: location)
        }.show()
        
    }
    
    /// 刷新Item
    func reloadPathItem(item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem) {
        if let index = path.items.firstIndex(of: item) {
            collectionView.reloadItems(at: [IndexPath(item: index + 1, section: 0)])
        }else {
            collectionView.reloadData()
        }
    }
    
}

extension GroupPathSequencePathViewCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return path.items.count + 2
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 || indexPath.item == collectionView.numberOfItems(inSection: indexPath.section) - 1 { // Add
            let addItem = collectionView.dequeueReusableCell(withReuseIdentifier: "addItem", for: indexPath) as! GroupPathSequencePathAddItem
            return addItem
        }else {
            let pathItem = collectionView.dequeueReusableCell(withReuseIdentifier: "pathItem", for: indexPath) as! GroupPathSequencePathItem
            let itemData = path.items[max(indexPath.item - 1, 0)]
            pathItem.sequenceLabel.text = "\(pathIndex + 1)-\(indexPath.item)"
            pathItem.boxView.layer.borderColor = RGB(241, 242, 244).cgColor
            if let node = itemData.node {
                pathItem.iconImageView.isHidden = false
                pathItem.nameLabel.isHidden = false
                pathItem.nameLabel.text = node.name
                pathItem.arrowImageView.isHidden = true
                if node.state {
                    pathItem.nameLabel.textColor = SubText_Color
                    pathItem.iconImageView.image = UIImage(named: "path_device")
                }else {
                    pathItem.nameLabel.textColor = AssistText_Color
                    pathItem.iconImageView.image = UIImage(named: "path_device_offline")
                }
                
            }else {
                // 当前选中的item
                if let selectPathData = selectPathData, selectPathData.path == path && selectPathData.item == itemData {
                    pathItem.arrowImageView.isHidden = false
                    var direction = selectPathData.direction
                    // 奇数行，排列为倒序，需要将方向调转
                    if indexPath.item / colCount % 2 == 1 {
                        direction = direction == .left ? .right : .left
                    }
                    pathItem.arrowImageView.image = UIImage(named: direction == .right ? "path_direction_right" : "path_direction_left")
                    pathItem.boxView.layer.borderColor = Yellow_Color.cgColor
                }else {
                    pathItem.arrowImageView.isHidden = true
                }
                pathItem.iconImageView.isHidden = true
                pathItem.nameLabel.isHidden = true
            }
            return pathItem
        }
    }
    
    //    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    //        var itemW = ((collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right) - CGFloat(colCount - 1) * flowLayout.minimumInteritemSpacing) / CGFloat(colCount)
    //        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
    //        return CGSize(width: itemW, height: SCRYFrom(62))
    //    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        if indexPath.item == 0 || indexPath.item == collectionView.numberOfItems(inSection: indexPath.section) - 1 { // Add
            if indexPath.row == 0 {
                delegate?.cell(self, didAddItem: 1, insertIndex: indexPath.row)
            }else {
                delegate?.cell(self, didAddItem: 1, insertIndex: indexPath.row - 1)
            }
            
        }else {
            guard let cell = collectionView.cellForItem(at: indexPath) else {
                return
            }
            let menuWidth = SCRXFrom(99)
            var options: [PathItemOptions] = []
            let pathItem = path.items[indexPath.row - 1]
            // 判断是否有设备
            if pathItem.node != nil {
                options = [.identify, .remove, .insertRight, .insertLeft, .delete]
            }else {
                // 判断是否是当前选中的item
                if selectPathData?.path == path && selectPathData?.item == pathItem {
                    options = [.overturn, .insertRight, .insertLeft, .delete]
                }else {
                    options = [.startRight, .startLeft, .insertRight, .insertLeft, .delete]
                }
            }
            
            
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
                case .overturn:
                    let direction: PathDirection = selectPathData?.direction == .left ? .right : .left
                    self.selectPathData?.direction = direction
                    self.delegate?.cell(self, didSelectDirection: pathItem, direction: direction)
                case .insertRight:
                    var index = indexPath.row
                    // 奇数行，排列为倒序，需要将方向调转
                    if indexPath.item / colCount % 2 == 1 {
                        index = min(indexPath.row - 1, 0)
                    }
                    self.delegate?.cell(self, didAddItem: 1, insertIndex: index)
                case .insertLeft:
                    var index = min(indexPath.row - 1, 0)
                    // 奇数行，排列为倒序，需要将方向调转
                    if indexPath.item / colCount % 2 == 1 {
                        index = indexPath.row
                    }
                    self.delegate?.cell(self, didAddItem: 1, insertIndex: index)
                case .startLeft:
                    self.selectPathData?.direction = .left
                    self.delegate?.cell(self, didSelectDirection: pathItem, direction: .left)
                case .startRight:
                    self.selectPathData?.direction = .right
                    self.delegate?.cell(self, didSelectDirection: pathItem, direction: .right)
                case .identify:
                    self.delegate?.cell(self, deviceIdentify: pathItem)
                case .remove:
                    self.delegate?.cell(self, removeDevice: pathItem)
                case .delete:
                    self.delegate?.cell(self, deleteItem: pathItem)
                }
                
            }
            
        }
    }
    
}

extension GroupPathSequencePathViewCell: UIDropInteractionDelegate {
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSString.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: NSString.self) {[weak self] items in
            guard let self = self, selectPathData?.path == self.path else { return }
            let dropPoint = session.location(in: self)
            let collectionPoint = self.convert(dropPoint, to: self.collectionView)
            
            guard let addressHex = items.first as? String, let address = Address(hex: addressHex), let indexPath = self.collectionView.indexPathForItem(at: collectionPoint), indexPath.row > 0 && indexPath.item - 1 < self.path.items.count else { return }
            
            let item = self.path.items[indexPath.item - 1]
            //                item.address = address
            //                self.collectionView.reloadItems(at: [indexPath])
            self.delegate?.cell(self, bindDevice: item, address: address)
        }
    }
    
}

class GroupPathSequencePathItem: UICollectionViewCell {
    
    var sequenceLabel: UILabel!
    var boxView: UIView!
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var arrowImageView: UIImageView!
    
    var boxSelectCallback: (()->Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        setupUI()
        
        boxView.layer.cornerRadius = self.width * 0.5
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    @objc private func boxViewTapGesture() {
        boxSelectCallback?()
    }
    
    private func setupUI() {
        
        sequenceLabel = UILabel(text: "1-1", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(sequenceLabel)
        sequenceLabel.snp.makeConstraints { make in
            make.centerX.top.equalToSuperview()
        }
        
        boxView = UIView()
        boxView.layer.borderColor = RGB(241, 242, 244).cgColor
        boxView.layer.borderWidth = 1
        //        boxView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(boxViewTapGesture)))
        contentView.addSubview(boxView)
        boxView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(boxView.snp.width)
        }
        
        iconImageView = UIImageView(image: UIImage(named: "path_device"))
        boxView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(3))
        }
        
        nameLabel = UILabel(text: "ID001", textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        boxView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.bottom.equalTo(SCRYFrom(-7))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "path_direction_right"))
        arrowImageView.isHidden = true
        boxView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
    }
    
}


class GroupPathSequencePathAddItem: UICollectionViewCell {
    
    var boxView: UIView!
    var addImageView: UIImageView!
    
    var boxSelectCallback: (()->Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        setupUI()
        
        boxView.layoutIfNeeded()
        boxView.layer.cornerRadius = boxView.height * 0.5
        
        if !(boxView.layer.sublayers?.contains(where: { $0.name == "deshed" }) ?? false) {
            boxView.addDashedBorder()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    @objc private func boxViewTapGesture() {
        boxSelectCallback?()
    }
    
    private func setupUI() {
        boxView = UIView()
        //        boxView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(boxViewTapGesture)))
        contentView.addSubview(boxView)
        boxView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(boxView.snp.width)
        }
        
        addImageView = UIImageView(image: UIImage(named: "path_item_add"))
        boxView.addSubview(addImageView)
        addImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
