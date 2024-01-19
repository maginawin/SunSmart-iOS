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
    var itmeColCount = 3
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = self.collectionView else { return }
        
        attrubutesArray.removeAll()
        let count = collectionView.numberOfItems(inSection: 0)
        for index in 0..<count {
            let indexPath = IndexPath(item: index, section: 0)
            if let attributes = layoutAttributesForItem(at: indexPath) {
                attrubutesArray.append(attributes)
            }
        }
    }
    
    override var collectionViewContentSize: CGSize {
        var contentSize = super.collectionViewContentSize
        if scrollDirection == .horizontal, let collectionView = collectionView, collectionView.isPagingEnabled {
            let collectionW = collectionView.frame.size.width
            if contentSize.width > collectionW {
                contentSize.width = CGFloat(Int(contentSize.width / collectionW) + 1) * collectionW
            }
        }
        return contentSize
    }
    
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        
        // 横向排列时调整系统排序方向
        // 0  3  6      0  1  2
        // 1  4  7  =>  3  4  5
        // 2  5  8      6  7  8
        guard scrollDirection == .horizontal else {
            return super.layoutAttributesForItem(at: indexPath)
        }
        
        let page = indexPath.item / (self.itmeColCount * self.itemRowCount) // 第几页(左右翻页)： 每行的cell个数 * 几行
        
        let itemX = indexPath.item % self.itmeColCount + page * self.itmeColCount //
        let itemY = indexPath.item / self.itmeColCount - page * self.itemRowCount //
        
        let item = itemX * self.itemRowCount + itemY
        let newIndexPath = IndexPath(item: item, section: indexPath.section)
        let attributes = super.layoutAttributesForItem(at: indexPath)
        if let newAttributes = super.layoutAttributesForItem(at: newIndexPath), let collectionView = self.collectionView, newIndexPath.item < collectionView.numberOfItems(inSection: 0) {
            
            var frame = newAttributes.frame
            if collectionView.isPagingEnabled {
                let contentInset = UIEdgeInsets(top: collectionView.contentInset.top + sectionInset.top, left: collectionView.contentInset.left + sectionInset.left, bottom: collectionView.contentInset.bottom + sectionInset.bottom, right: collectionView.contentInset.right + sectionInset.right)
                frame.origin.x += CGFloat(page) * (contentInset.left)
            }
            attributes?.frame = frame
        }
        //            newAttributes?.indexPath = newIndexPath
        return attributes
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
      
        guard let layoutAttributesForElements = super.layoutAttributesForElements(in: rect) else {
            return nil
        }
        
        let resultElements = self.attrubutesArray.filter { element in
            return layoutAttributesForElements.contains(where: { $0.indexPath == element.indexPath })
        }
        
        return resultElements
    }
    
}
