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
    
    weak var delegate: CustomSegmentedControlDelegate?
    
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
    
    /// 选中的滑块背景颜色
    var selectBgColor: UIColor = Bar_Color {
        didSet {
            selectBgView.backgroundColor = selectBgColor
        }
    }
    
    var titleFont: UIFont = UIFont.systemFont(ofSize: SCRYFrom(14)) {
        didSet {
            actionBtns.forEach({
                $0.titleLabel?.font = titleFont
            })
        }
    }
    
    
    /// 选中的滑块标题颜色
    var selectTitleColor: UIColor = .white {
        didSet {
            actionBtns.forEach({
                $0.setTitleColor(selectTitleColor, for: .selected)
            })
        }
    }
    
    var selectBorderWidth: CGFloat = 1 {
        didSet {
            selectBgView.layer.borderWidth = selectBorderWidth
        }
    }
    
    /// 选中的滑块边框颜色
    var selectBorderColor: UIColor = .clear {
        didSet {
            selectBgView.layer.borderColor = selectBorderColor.cgColor
//            if selectedIndex < self.actionBtns.count {
//                self.actionBtns[selectedIndex].layer.shadowColor = selectBorderColor.cgColor
//            }
        }
    }
    
    /// 展示阴影
    var showShadow: Bool = true {
        didSet {
            selectBgView.layer.shadowOpacity = showShadow ? 1 : 0
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
        guard delegate?.segmentedControl(self, shouldSelesctedItem: index) ?? true else {
            return
        }
        
        let lastBtn = actionBtns[selectedIndex]
        lastBtn.isSelected = false
//        lastBtn.layer.borderWidth = 0
        selectedIndex = index
        
        let selectBtn = actionBtns[index]
        selectBtn.isSelected = true
//        selectBtn.layer.borderWidth = 0.5
//        selectBtn.layer.borderColor = selectBorderColor.cgColor
        
        UIView.animate(withDuration: 0.3) {
            self.selectBgView.x = self.margin + CGFloat(self.selectedIndex) * self.selectBgView.width
        }
        
        delegate?.segmentedControl(self, didSelectedItem: index)
    }
    
    private func setupUI() {
        
        selectBgView = UIView()
        selectBgView.backgroundColor = selectBgColor
        selectBgView.layer.cornerRadius = cornerRadius
        selectBgView.layer.borderWidth = selectBorderWidth
        selectBgView.layer.borderColor = selectBorderColor.cgColor
        if showShadow {
            selectBgView.layer.shadowColor = RGB(82, 82, 153, 0.12).cgColor
            selectBgView.layer.shadowOffset = CGSizeMake(0,3)
            selectBgView.layer.shadowOpacity = 1
            selectBgView.layer.shadowRadius = cornerRadius
        }
        addSubview(selectBgView)
        
        for (index, title) in titles.enumerated() {
            let btn = UIButton(title: title, titleSize: 14, titleColor: RGB(156, 163, 175), target: self, action: #selector(actionBtnClick))
            btn.titleLabel?.font = titleFont
            btn.tag = 100 + index
            btn.setTitleColor(selectTitleColor, for: .selected)
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

protocol CustomSegmentedControlDelegate: AnyObject {
    
    /// 分段控制器是否可以点击item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, shouldSelesctedItem index: Int) -> Bool
    
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int)
}

extension CustomSegmentedControlDelegate {
    
    /// 分段控制器是否可以点击item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, shouldSelesctedItem index: Int) -> Bool {
        return true
    }
    
}
