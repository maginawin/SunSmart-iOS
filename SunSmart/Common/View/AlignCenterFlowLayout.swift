//
//  AlignCenterFlowLayout.swift
//  TestDemo
//
//  Created by 袁科鸿 on 2023/12/1.
//

import UIKit

class AlignCenterFlowLayout: UICollectionViewFlowLayout {

    var attrubutesArray: [UICollectionViewLayoutAttributes] = []
    // 每行item个数
    var itemRowCount = 3
    // 每列item个数
    var itmeColCount = 3
    /// y轴偏移量（居中时）
    var offsetY: CGFloat = 0
    
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = self.collectionView else { return }
        
        attrubutesArray.removeAll()
        let count = collectionView.numberOfItems(inSection: 0)
                
        let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
        
        // 计算每个item的尺寸
        var itemWidth = (collectionView.bounds.width - contentInset.left - contentInset.right - minimumInteritemSpacing * CGFloat(itemRowCount - 1)) / CGFloat(itemRowCount)
        var itemHeight = itemWidth
        if itemSize != .zero && itemSize != CGSize(width: 50, height: 50) {
            itemWidth = itemSize.width
            itemHeight = itemSize.height
        }
        
        for index in 0..<count {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            if scrollDirection == .horizontal {
                let pageIndex = index / (self.itmeColCount * self.itemRowCount)
                let row = index % self.itemRowCount + pageIndex * self.itemRowCount
                let column = index / self.itemRowCount - pageIndex * self.itmeColCount
                
                let x = contentInset.left + CGFloat(row) * (itemWidth + minimumInteritemSpacing) + CGFloat(pageIndex) * (contentInset.left + contentInset.right - minimumInteritemSpacing)
                
                let y = sectionInset.top + CGFloat(column) * (itemHeight + minimumLineSpacing)
                
                let frame = CGRect(x: x, y: y, width: itemWidth, height: itemHeight)
                attributes.frame = frame
                attrubutesArray.append(attributes)
            }else {
                if let attributes = super.layoutAttributesForItem(at: indexPath) {
                    attrubutesArray.append(attributes)
                }
            }
        }
        
        let showHeight = collectionView.frame.size.height - contentInset.top - contentInset.bottom

        // 判断最后一行展示数据不全是否需要水平居中
        let lastRow = attrubutesArray.count / itemRowCount
        var page = 0
        var maxX = collectionView.frame.size.width - contentInset.right - contentInset.left
        
        // 最后一页元素
        var lagePageElements = attrubutesArray
        
        if scrollDirection == .horizontal {
            page = Int(ceil(CGFloat(attrubutesArray.count) / CGFloat(self.itmeColCount * self.itemRowCount)))
            maxX = CGFloat(page) * collectionView.frame.size.width - contentInset.right
            lagePageElements = attrubutesArray.filter({ Int(ceil(CGFloat($0.indexPath.item + 1) / CGFloat(self.itmeColCount * self.itemRowCount))) >= page})
        }
        
        // 最后一行元素
        let lastRowElements = attrubutesArray.filter({ $0.indexPath.item / itemRowCount >= lastRow})
        if let lastElement = lastRowElements.last, lastRowElements.count < itemRowCount {
            lastRowElements.forEach({
                var frame = $0.frame
                let leftMargin: CGFloat = 0
//                attrubutesArray.count <= itemRowCount ? 0 : collectionView.contentInset.left
                frame.origin.x += (maxX - lastElement.frame.maxX + leftMargin) * 0.5
                $0.frame = frame
            })
        }

        let lastPageMaxY = lagePageElements.last?.frame.maxY ?? 0
        // 判断内容高度小于collectionview高度时垂直居中
        if showHeight - lastPageMaxY >= 1 {
            lagePageElements.forEach({
                var frame = $0.frame
                var top = frame.origin.y
                top += (showHeight - lastPageMaxY  + offsetY) * 0.5 // + collectionView.contentOffset.y
                frame.origin.y = top
                $0.frame = frame
            })
        }
        
    }
    
    override var collectionViewContentSize: CGSize {
        guard let collectionView = collectionView, self.scrollDirection == .horizontal else {
            return super.collectionViewContentSize
        }
          
          let itemCount = collectionView.numberOfItems(inSection: 0)
        let pages = ceil(Double(itemCount) / Double(self.itemRowCount * self.itmeColCount))
          let width = collectionView.bounds.width * CGFloat(pages)
        return CGSize(width: width, height: collectionView.bounds.size.height - collectionView.contentInset.top - collectionView.contentInset.bottom)
      }
    
    
//    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//        
//        // 横向排列时调整系统排序方向
//        // 0  3  6      0  1  2
//        // 1  4  7  =>  3  4  5
//        // 2  5  8      6  7  8
//        guard scrollDirection == .horizontal else {
//            return super.layoutAttributesForItem(at: indexPath)
//        }
//        
//        let page = indexPath.item / (self.itmeColCount * self.itemRowCount) // 第几页(左右翻页)： 每行的cell个数 * 几行
//        
//        let itemX = indexPath.item % self.itemRowCount + page * self.itemRowCount //
//        let itemY = indexPath.item / self.itemRowCount - page * self.itmeColCount //
//        
//        let item = itemX * self.itmeColCount + itemY
//        let newIndexPath = IndexPath(item: item, section: indexPath.section)
//        let attributes = super.layoutAttributesForItem(at: indexPath)
//        if let newAttributes = super.layoutAttributesForItem(at: newIndexPath), let collectionView = self.collectionView {
//            
//            let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
//            
//            var frame = newAttributes.frame
//            frame.origin.x += CGFloat(page) * (contentInset.left + contentInset.right - minimumInteritemSpacing)
//            attributes?.frame = frame
////            print("item:\(newIndexPath.item) frame: \(frame)")
//        }
//        //            newAttributes?.indexPath = newIndexPath
//        return attributes
//    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return attrubutesArray.filter { $0.frame.intersects(rect) }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return attrubutesArray[indexPath.item]
    }
    
}
