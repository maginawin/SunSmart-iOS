//
//  MultiseriatePickerView.swift
//  EasyThingsPro
//
//  Created by 袁科鸿 on 2024/1/8.
//

import UIKit

class MultiseriatePickerView: UIView {

    typealias PickerCallback = (([Int])->Void)
    
    var pickerView: UIPickerView!
    
    private var titles: [[String]] = []
//    private var defaultSelectRows: [Int] = []
    var pickerBack: PickerCallback?
    
    private var isAddPickerLine: Bool = false
    
    var selectRows: [Int] {
        get {
            var selectRows: [Int] = []
            for component in 0..<self.pickerView.numberOfComponents {
                let row = self.pickerView.selectedRow(inComponent: component)
                selectRows.append(row)
            }
            return selectRows
        }set {
            for (section, row) in newValue.enumerated() {
                if section < self.titles.count, row < self.titles[section].count {
                    self.pickerView.selectRow(row, inComponent: section, animated: false)
                }
            }
        }
    }
    
    
//    static func show(titles: [[String]], defaultSelectRows: [Int] = [], pickerBack: @escaping PickerCallback) {
//        
//        let view = MultiseriatePickerView(frame: UIScreen.main.bounds)
//        view.titles = titles
//        view.defaultSelectRows = defaultSelectRows
//        view.pickerBack = pickerBack
//        UIApplication.shared.keyWindow().addSubview(view)
//        view.showAnimation()
//        view.setPickerDefalutValue()
//    }
    
    init(frame: CGRect, titles: [[String]]) {
        
        super.init(frame: frame)
        
        self.titles = titles
        
        setupUI()
//        setPickerDefalutValue()
    }
    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        
//        setupUI()
//    }
//    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setPickerDefalutValue() {
        
//        for (section, row) in self.defaultSelectRows.enumerated() {
//            if section < self.titles.count, row < self.titles[section].count {
//                self.pickerView.selectRow(row, inComponent: section, animated: false)
//            }
//        }
        
    }
    
//    private func showAnimation() {
//        
//        self.shadeView.alpha = 0
//        self.contentView.alpha = 0
//        UIView.animate(withDuration: 0.3) {
//            self.shadeView.alpha = 1
//            self.contentView.alpha = 1
//        } completion: { _ in
//            
//        }
//    }
    
//    @objc private func hide() {
//        
//        var selectRows: [Int] = []
//        for component in 0..<self.pickerView.numberOfComponents {
//            let row = self.pickerView.selectedRow(inComponent: component)
//            selectRows.append(row)
//        }
//        
//        pickerBack?(selectRows)
//        
//        UIView.animate(withDuration: 0.3) {
//            self.shadeView.alpha = 0
//            self.contentView.alpha = 0
//        } completion: { _ in
//            self.removeFromSuperview()
//        }
//
//    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 隐藏之前的选中框
        if let backgroundView = pickerView.subviews.last {
            backgroundView.backgroundColor = .clear
            
            // 添加分割线
            if !isAddPickerLine {
                isAddPickerLine = true
                let topLineView = UIView()
                topLineView.backgroundColor = RGB(218, 218, 218, 0.7)
                self.addSubview(topLineView)
                topLineView.snp.makeConstraints { make in
                    make.left.equalTo(30)
                    make.right.equalTo(-30)
                    make.height.equalTo(1)
                    make.top.equalTo(backgroundView)
                }
                
                let bottomLineView = UIView()
                bottomLineView.backgroundColor = RGB(218, 218, 218, 0.7)
                self.addSubview(bottomLineView)
                bottomLineView.snp.makeConstraints { make in
                    make.left.right.height.equalTo(topLineView)
                    make.bottom.equalTo(backgroundView)
                }
            }
            
        }
    }
    
    private func setupUI() {
        
//        shadeView = UIView()
//        shadeView.backgroundColor = RGB(0, 0, 0, 0.5)
//        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hide)))
//        addSubview(shadeView)
//        shadeView.snp.makeConstraints { make in
//            make.edges.equalToSuperview()
//        }
        
//        contentView = UIView()
//        contentView.backgroundColor = RGB(19, 19, 23)
//        contentView.layer.cornerRadius = SCRYFrom(20)
//        addSubview(contentView)
//        contentView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(10))
//            make.right.equalTo(SCRXFrom(-10))
//            make.bottom.equalTo(isIphoneX ? SCRYFrom(-40) : SCRYFrom(-10))
//            make.height.equalTo(SCRYFrom(246))
//        }
        
        pickerView = UIPickerView()
        pickerView.dataSource = self
        pickerView.delegate = self
        addSubview(pickerView)
        pickerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-26))
            make.top.equalTo(SCRYFrom(24))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        
    }

}

extension MultiseriatePickerView: UIPickerViewDataSource, UIPickerViewDelegate {
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return titles.count
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return titles[component].count
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let titleLabel = view as? UILabel ?? UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(19), weight: .light)
        titleLabel.textColor = RGB(39, 37, 53)
        titleLabel.text = titles[component][row]
//        titleLabel.width = pickerView.width / 3.0
        titleLabel.textAlignment = .center
        return titleLabel
    }
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return SCRYFrom(40)
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerBack != nil {
            var list = Array(repeating: 0, count: pickerView.numberOfComponents)
            for number in 0..<pickerView.numberOfComponents {
                list[number] = pickerView.numberOfRows(inComponent: number)
            }
            pickerBack?(list)
        }
    }
    
}
