//
//  HorizontalDirectionFlowLayout.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/12.
//

import UIKit

class HorizontalDirectionFlowLayout: UICollectionViewFlowLayout {

    var attrubutesArray: [UICollectionViewLayoutAttributes] = []
    // 每行item个数
    var itemRowCount = 3
    // 每列item个数
    var itemColCount = 3
    
    var itemHeight: CGFloat?
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = self.collectionView else { return }
        
        attrubutesArray.removeAll()
        let count = collectionView.numberOfItems(inSection: 0)
                
        let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
        
        // 计算每个item的尺寸
        var itemWidth = (collectionView.bounds.width - contentInset.left - contentInset.right - minimumInteritemSpacing * CGFloat(itemRowCount - 1)) / CGFloat(itemRowCount)
        var itemHeight = itemHeight ?? itemWidth
        if itemSize != .zero && itemSize != CGSize(width: 50, height: 50) {
            itemWidth = itemSize.width
            itemHeight = itemSize.height
        }
        
        for index in 0..<count {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            if scrollDirection == .horizontal {
                let pageIndex = index / (self.itemColCount * self.itemRowCount)
                let row = index % self.itemRowCount + pageIndex * self.itemRowCount
                let column = index / self.itemRowCount - pageIndex * self.itemColCount
                
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
        
//        attrubutesArray.removeAll()
//        let count = collectionView.numberOfItems(inSection: 0)
//        for index in 0..<count {
//            let indexPath = IndexPath(item: index, section: 0)
//            if let attributes = layoutAttributesForItem(at: indexPath) {
//                attrubutesArray.append(attributes)
//            }
//        }
    }
    
    override var collectionViewContentSize: CGSize {
        var contentSize = super.collectionViewContentSize
        if scrollDirection == .horizontal, let collectionView = collectionView, collectionView.isPagingEnabled {
            
            let itemCount = collectionView.numberOfItems(inSection: 0)
          let pages = ceil(Double(itemCount) / Double(self.itemRowCount * self.itemColCount))
            
            let collectionW = collectionView.frame.size.width
            
            let width = collectionW * CGFloat(pages)
            contentSize = CGSize(width: width, height: collectionView.bounds.size.height - collectionView.contentInset.top - collectionView.contentInset.bottom)
            
//            let margin = collectionView.contentInset.left + sectionInset.left
//            let collectionW = collectionView.frame.size.width - margin
//            if contentSize.width > collectionW - margin {
//                
//                contentSize.width = CGFloat(ceilf(Float(contentSize.width / collectionW))) * collectionW
////                - collectionView.contentInset.left - collectionView.contentInset.right
//            }
        }
        return contentSize
    }
    
    
//    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//        
//        // 横向排列时调整系统排序方向
//        // 0  3  6      0  1  2
//        // 1  4  7  =>  3  4  5
//        // 2  5  8      6  7  8
//        guard let collectionView = self.collectionView, scrollDirection == .horizontal, let attributes = super.layoutAttributesForItem(at: indexPath) else {
//            return super.layoutAttributesForItem(at: indexPath)
//        }
//        
//        let page = indexPath.item / (self.itmeColCount * self.itemRowCount) // 第几页(左右翻页)： 每行的cell个数 * 几行
//        
//        let itemX = indexPath.item % self.itmeColCount + page * self.itmeColCount //
//        let itemY = indexPath.item / self.itmeColCount - page * self.itemRowCount //
////        Int(collectionView.contentSize.height) != Int(collectionView.frame.size.height)
////        let item = itemX * self.itemRowCount + itemY
////        let newIndexPath = IndexPath(item: item, section: indexPath.section) 
//        
//        let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
//        
//        var frame = attributes.frame
//        let itemW = frame.size.width
//        let itemH = frame.size.height
//        
//        
//        frame.origin.x = contentInset.left + CGFloat(itemX) * (itemW + minimumInteritemSpacing) + CGFloat(page) * (contentInset.left + contentInset.right - minimumInteritemSpacing)
////        sectionInset.left + CGFloat(itemX) * (itemW + minimumInteritemSpacing)
//        frame.origin.y = sectionInset.top + CGFloat(itemY) * (itemH + minimumInteritemSpacing)
//        attributes.frame = frame
//        return attributes
//        
//        
//        
////        if let newAttributes = super.layoutAttributesForItem(at: newIndexPath), newIndexPath.item < collectionView.numberOfItems(inSection: 0) {
////            
////            var frame = newAttributes.frame
////            if collectionView.isPagingEnabled {
////                let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
////                frame.origin.x += CGFloat(page) * (contentInset.left)
////            }
////            attributes?.frame = frame
////        }
////        //            newAttributes?.indexPath = newIndexPath
////        return attributes
//    }
    
//    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
//      
//        guard let layoutAttributesForElements = super.layoutAttributesForElements(in: rect) else {
//            return nil
//        }
//        
//        let resultElements = self.attrubutesArray.filter { element in
//            return layoutAttributesForElements.contains(where: { $0.indexPath == element.indexPath })
//        }
//        
//        return resultElements
//    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return attrubutesArray.filter { $0.frame.intersects(rect) }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return attrubutesArray[indexPath.item]
    }
    
}
