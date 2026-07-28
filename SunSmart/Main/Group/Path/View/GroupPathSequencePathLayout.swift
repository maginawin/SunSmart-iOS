//
//  GroupPathSequencePathLayout.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

enum GroupPathSequenceDeviceItemMetrics {
    static let controlSize: CGFloat = 44
    static let controlCornerRadius: CGFloat = 22
    static let imageSize: CGFloat = 20
    static let sequenceLabelHeight: CGFloat = 16
    static let sequenceItemHeight: CGFloat = 60
    static let lineSpacing: CGFloat = 8
    static let sequenceVerticalInset: CGFloat = 10
    static let triggerZoneSectionInset: CGFloat = 16
    static let triggerZoneMinimumHeight: CGFloat = 60
    static let imageTopSpacing: CGFloat = 3
    static let imageNameSpacing: CGFloat = 2
}

class GroupPathSequencePathLayout: UICollectionViewFlowLayout {
    
    private var lineWidth: CGFloat = 1
    private var cornerLineWidth: CGFloat = 8
    private var lineColor: UIColor = Message_Color
    var colCount: Int = 5
    var itemHeight: CGFloat = GroupPathSequenceDeviceItemMetrics.sequenceItemHeight
    
    // 布局缓存
    private var itemAttributes: [UICollectionViewLayoutAttributes] = []
    private var lineAttributes: [UICollectionViewLayoutAttributes] = []
    
    // 内容尺寸
    private var contentWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = self.collectionView else { return }
        
        
        self.register(ConnectingLineView.self, forDecorationViewOfKind: "ConnectingLine")
        
        let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
        
        // 计算每个item的尺寸
        var itemWidth = (collectionView.bounds.width - contentInset.left - contentInset.right - minimumInteritemSpacing * CGFloat(colCount - 1)) / CGFloat(colCount)
        itemWidth = CGFloat(floorf(Float(itemWidth) * 100) / 100.0)
        itemSize = CGSize(width: itemWidth, height: itemHeight)
        
        // 重置缓存
        itemAttributes.removeAll()
        lineAttributes.removeAll()
        
        // 计算内容宽度
        contentWidth = collectionView.bounds.width
        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        
        // 计算总行数
        let rowCount = Int(ceil(Double(numberOfItems) / Double(colCount)))
        
        // 计算内容高度
        contentHeight = CGFloat(rowCount) * (itemSize.height + minimumLineSpacing)
        
        // 调整系统排序
        // 1  2  3   4   5    =>   1   2   3   4   5
        // 6  7  8   9   10        10  9   8   7   6
        
        // 计算每个item的位置
        for item in 0..<numberOfItems {
            let indexPath = IndexPath(item: item, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            
            // 计算行和列
            let row = item / colCount
            let isEvenRow = row % 2 == 0
            let col = isEvenRow ? item % colCount : (colCount - 1) - (item % colCount)
            
            // 计算位置
            let x = CGFloat(col) * (itemSize.width + minimumInteritemSpacing)
            let y = CGFloat(row) * (itemSize.height + minimumLineSpacing)
            
            attributes.frame = CGRect(x: x, y: y, width: itemSize.width, height: itemSize.height)
            itemAttributes.append(attributes)
            //            ConnectingLine
            // 如果是第一个item之后，添加连接线
            if item > 0 {
                let currentItem = item
                let prevItem = item - 1
                let lineAttributes = createLineAttributes(from: prevItem, to: currentItem)
                self.lineAttributes.append(lineAttributes)
            }
        }
        
    }
    
    private func centerForItem(at index: Int) -> CGPoint {
        let row = index / colCount
        let isEvenRow = row % 2 == 0
        let col = isEvenRow ? index % colCount : (colCount - 1) - (index % colCount)
        
        let x = CGFloat(col) * (itemSize.width + minimumInteritemSpacing) + itemSize.width/2
        let y = CGFloat(row) * (itemSize.height + minimumLineSpacing) + itemSize.height/2
        
        return CGPoint(x: x, y: y)
    }
    
    private func createLineAttributes(from: Int, to: Int) -> LineAttributes {
        let indexPath = IndexPath(item: to, section: 0)
        let attributes = LineAttributes(forDecorationViewOfKind: "ConnectingLine", with: indexPath)
        
        // 设置连接线样式
        attributes.color = lineColor
        attributes.lineWidth = lineWidth
        attributes.cornerLineWidth = cornerLineWidth
        // 判断是否是转角
        let fromRow = from / colCount
        let toRow = to / colCount
        attributes.lineType = (fromRow != toRow) ? .corner : .straight
        
        // 判断是否需要反向
        let isFromEven = (fromRow % 2 == 0)
        let isToEven = (toRow % 2 == 0)
        attributes.isReversed = isFromEven && !isToEven
        
        // 计算frame
        let fromCenter = centerForItem(at: from)
        let toCenter = centerForItem(at: to)
        
        var x = min(fromCenter.x, toCenter.x) - lineWidth/2
        var width = abs(fromCenter.x - toCenter.x) + attributes.lineWidth
        if fromRow != toRow {
            width = cornerLineWidth
            if attributes.isReversed {
                x = fromCenter.x + GroupPathSequenceDeviceItemMetrics.controlSize * 0.5
            }else {
                x = fromCenter.x - GroupPathSequenceDeviceItemMetrics.controlSize * 0.5 - width
            }
        }
        attributes.frame = CGRect(
            x: x,
            y: min(fromCenter.y, toCenter.y) - attributes.lineWidth/2 + (self.collectionView?.contentInset.top ?? 0),
            width: width,
            height: abs(fromCenter.y - toCenter.y) + attributes.lineWidth
        )
        
        attributes.zIndex = -1
        return attributes
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var visibleAttributes: [UICollectionViewLayoutAttributes] = []
        
        // 添加可见的item属性
        for attributes in itemAttributes {
            if attributes.frame.intersects(rect) {
                visibleAttributes.append(attributes)
            }
        }
        
        // 添加可见的连接线属性
        for attributes in lineAttributes {
            if attributes.frame.intersects(rect) {
                visibleAttributes.append(attributes)
            }
        }
        
        return visibleAttributes
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return itemAttributes[indexPath.item]
    }
    
    override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        if elementKind == "ConnectingLine" {
            return lineAttributes.first { $0.indexPath == indexPath }
        }
        return nil
    }
    
//    override var collectionViewContentSize: CGSize {
//        return CGSize(width: contentWidth, height: contentHeight)
//    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
}

class LineAttributes: UICollectionViewLayoutAttributes {
    var color: UIColor = .red
    var lineWidth: CGFloat = 1
    var cornerLineWidth: CGFloat = 8
    var lineType: ConnectingLineView.LineType = .straight
    var isReversed: Bool = false
    
    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! LineAttributes
        copy.color = color
        copy.lineWidth = lineWidth
        copy.lineType = lineType
        copy.isReversed = isReversed
        return copy
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? LineAttributes else { return false }
        return super.isEqual(object) &&
        color == other.color &&
        lineWidth == other.lineWidth &&
        lineType == other.lineType &&
        isReversed == other.isReversed
    }
}

class ConnectingLineView: UICollectionReusableView {
    
    enum LineType {
        case straight    // 直线
        case corner      // 直角转角
    }
    
    var color: UIColor = Message_Color {
        didSet {
            self.setNeedsDisplay()
        }
    }
    var lineWidth: CGFloat = 1 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    var cornerLineWidth: CGFloat = 8 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    var lineType: LineType = .straight {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    var isReversed: Bool = false {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        
        guard let attr = layoutAttributes as? LineAttributes else { return }
        self.color = attr.color
        self.lineWidth = attr.lineWidth
        self.lineType = attr.lineType
        self.isReversed = attr.isReversed
        self.cornerLineWidth = attr.cornerLineWidth
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        let cornerSize: CGFloat = 8 // 直角转角的大小
        
        switch lineType {
        case .straight:
            // 绘制直线
            context.move(to: CGPoint(x: 0, y: 0))
                context.addLine(to: CGPoint(x: bounds.width, y: 0))
 
        case .corner:

            let path = UIBezierPath()
            if isReversed {
                // 反向 "]"
                let startPoint = CGPoint(x: bounds.minX, y: bounds.minY)
                let endPoint = CGPoint(x: bounds.minX, y: bounds.maxY)
                
                path.move(to: startPoint)
                path.addLine(to: CGPoint(x: bounds.minX + cornerSize, y: bounds.minY))
                path.addLine(to: CGPoint(x: bounds.minX + cornerSize, y: bounds.maxY))
                path.addLine(to: endPoint)

            } else {
                // 正向 "]"
                
                let startPoint = CGPoint(x: bounds.maxX, y: bounds.minY)
                let endPoint = CGPoint(x: bounds.maxX, y: bounds.maxY)
                
                path.move(to: startPoint)
                path.addLine(to: CGPoint(x: bounds.maxX - cornerSize, y: bounds.minY))
                path.addLine(to: CGPoint(x: bounds.maxX - cornerSize, y: bounds.maxY))
                path.addLine(to: endPoint)

            }
            context.addPath(path.cgPath)
        }
        
        context.strokePath()
    }
}
