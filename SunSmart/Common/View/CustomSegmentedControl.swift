//
//  CustomSegmentedControl.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/22.
//

import UIKit

class CustomSegmentedControl: UIView {

    private var actionBtns: [UIButton] = []
    private var selectBgView: UIView!
    private var titles: [String] = []
    private var selectedActionBtn: UIButton?
    
    var delegate: CustomSegmentedControlDelegate?
    
    var cornerRadius: CGFloat = SCRYFrom(8)
    
    var selectedIndex: Int = 0 {
        willSet {
            actionBtns[selectedIndex].isSelected = false
        }
        didSet {
            self.actionBtns[selectedIndex].isSelected = true
            guard !self.frame.isEmpty else {
                return
            }
            UIView.animate(withDuration: 0.3) {
                self.selectBgView.x = self.margin + CGFloat(self.selectedIndex) * self.selectBgView.width
            }
        }
    }
    
    // 内边距
    var margin: CGFloat = 4 {
        didSet {
            updateFrame()
        }
    }
    
    
    init(frame: CGRect, titles: [String]) {
        super.init(frame: frame)
        
        self.layer.cornerRadius = cornerRadius
        self.layer.borderColor = RGB(238, 238, 239).cgColor
        self.layer.borderWidth = 1
        
        self.titles = titles
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateFrame()
    }
    
    @objc private func actionBtnClick(sender: UIButton) {
        
        let index = sender.tag - 100
        guard index != selectedIndex else {
            return
        }
        actionBtns[selectedIndex].isSelected = false
        selectedIndex = index
        self.actionBtns[index].isSelected = true
        
        UIView.animate(withDuration: 0.3) {
            self.selectBgView.x = self.margin + CGFloat(self.selectedIndex) * self.selectBgView.width
        }
        
        delegate?.segmentedControl(self, didSelectedItem: index)
    }
    
    private func setupUI() {
        
        selectBgView = UIView()
        selectBgView.backgroundColor = Bar_Color
        selectBgView.layer.cornerRadius = cornerRadius
        selectBgView.layer.shadowColor = RGB(82, 82, 153, 0.12).cgColor
        selectBgView.layer.shadowOffset = CGSizeMake(0,3)
        selectBgView.layer.shadowOpacity = 1
        selectBgView.layer.shadowRadius = cornerRadius
        addSubview(selectBgView)
        
        for (index, title) in titles.enumerated() {
            let btn = UIButton(title: title, titleSize: 14, titleColor: RGB(156, 163, 175), target: self, action: #selector(actionBtnClick))
            btn.tag = 100 + index
            btn.setTitleColor(.white, for: .selected)
            if index == selectedIndex {
                btn.isSelected = true
            }
            addSubview(btn)
            actionBtns.append(btn)
        }
        selectedActionBtn = actionBtns.first
        
        updateFrame()
    }
    
    private func updateFrame() {
        guard !self.frame.isEmpty else {
            return
        }
        let itemW = (self.frame.width - margin * 2) / CGFloat(actionBtns.count)
        let itemH = self.frame.height - margin * 2
        for (index, btn) in actionBtns.enumerated() {
            btn.frame = CGRect(x: margin + CGFloat(index) * itemW, y: margin, width: itemW, height: itemH)
        }
        selectBgView.frame = CGRect(x: margin + CGFloat(selectedIndex) * itemW, y: margin, width: itemW, height: itemH)
    }
    
}

protocol CustomSegmentedControlDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int)
}
