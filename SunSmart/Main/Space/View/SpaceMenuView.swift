//
//  SpaceMenuView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/26.
//

import UIKit

class SpaceMenuView: UIView {

    private var itemBtns: [UIButton] = []
    var selectIndex: Int = 0 {
        willSet {
            guard newValue < itemBtns.count else { return }
            itemBtns[selectIndex].isSelected = false
        }
        didSet {
            itemBtns[selectIndex].isSelected = true
        }
    }
    
    var margin: CGFloat = SCRXFrom(16)
    var itemMargin: CGFloat = SCRXFrom(6)
    
    var itemDatas: [MenuItemData]! {
        didSet {
            
            itemBtns.forEach({ $0.removeFromSuperview() })
            itemBtns.removeAll()
             
            for (index, itemData) in itemDatas.enumerated() {
                let btn = UIButton(title: itemData.title, titleSize: 12, titleWeight: .light, titleColor: RGB(148, 163, 184), normalImageName: itemData.imageName, selectedImageName: itemData.selectImageName, target: nil, action: nil)
                btn.setTitleColor(Bar_Color, for: .selected)
                btn.contentHorizontalAlignment = .center
                btn.isUserInteractionEnabled = false
                if index == selectIndex {
                    btn.isSelected = true
                }
                addSubview(btn)
                itemBtns.append(btn)
            }
            
            if !frame.isEmpty {
                updateItemsFrame()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateItemsFrame() {
        
        let itemW: CGFloat = (self.frame.size.width - margin * CGFloat(2) - CGFloat(itemBtns.count - 1) * itemMargin) / CGFloat(itemBtns.count)
        for (index, itemBtn) in itemBtns.enumerated() {
            itemBtn.frame = CGRect(x: margin + (itemW + itemMargin) * CGFloat(index), y: 0, width: itemW, height: self.frame.size.height - 6)
            itemBtn.setImagePosition(position: .top, spacing: 0)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateItemsFrame()
    }

}

extension SpaceMenuView {
    
    /// menu item信息
    static var defalutItems: [MenuItemData] {
        return [
            MenuItemData(title: "main".localizedString, imageName: "space_main", selectImageName: "space_main_selected"),
            MenuItemData(title: "group".localizedString, imageName: "space_group", selectImageName: "space_group_selected"),
            MenuItemData(title: "scene".localizedString, imageName: "space_scene", selectImageName: "space_scene_selected"),
            MenuItemData(title: "timed".localizedString, imageName: "space_timed", selectImageName: "space_timed_selected"),
            MenuItemData(title: "More".localizedString, imageName: "space_more", selectImageName: "space_more_selected")
        ]
    }
    
    struct MenuItemData {
        let title: String
        let imageName: String
        let selectImageName: String
    }
    
}
