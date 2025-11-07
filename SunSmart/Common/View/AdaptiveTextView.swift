//
//  AdaptiveTextView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/8.
//

import UIKit

class AdaptiveTextView: UITextView {
    
    var maxFontSize: CGFloat = 14
    var minFontSize: CGFloat = 10
    var fontWeight: UIFont.Weight = .light
    var lineHeightMultiple: CGFloat = 0.9
    
    // ✅ 兼容 UILabel 的 text 属性
    override var text: String! {
        didSet { adaptiveText = text }
    }
    
    // ✅ 兼容 UILabel 的 textColor 属性
    override var textColor: UIColor! {
        didSet { updateText() }
    }
    
    private var adaptiveText: String? {
        didSet { updateText() }
    }
    
    // MARK: - Init
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        isEditable = false
        isUserInteractionEnabled = false
        isScrollEnabled = false
        isSelectable = false
        backgroundColor = .clear
        textAlignment = .center
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
    }
    
    // MARK: - Update Logic
    private func updateText() {
        guard let rawText = adaptiveText, !rawText.isEmpty else {
            self.attributedText = nil
            return
        }
        
        // 1️⃣ 尝试用最大字号渲染，判断是否能在一行内放下
        let maxAttr = makeAttr(rawText, font: UIFont.systemFont(ofSize: maxFontSize, weight: fontWeight))
        let maxSize = bounding(maxAttr)
        
        if maxSize.height <= singleLineHeight(fontSize: maxFontSize) && maxSize.width <= bounds.width {
            // ✅ 一行能放下 → 最大字号直接显示
            self.attributedText = maxAttr
            return
        }
        
        // 2️⃣ 多行 → 从大到小缩小字号
        var fontSize = maxFontSize
        var fits = false
        
        while fontSize >= minFontSize {
            let attr = makeAttr(rawText, font: UIFont.systemFont(ofSize: fontSize, weight: fontWeight))
            let size = bounding(attr)
            if size.height <= bounds.height && size.width <= bounds.width {
                self.attributedText = attr
                fits = true
                break
            }
            fontSize -= 0.1
        }
        
        // 3️⃣ 缩到最小还不行 → 裁剪第一行前部，加 …
        if !fits {
            let font = UIFont.systemFont(ofSize: minFontSize, weight: fontWeight)
            var text = rawText
            var result: NSAttributedString?
            
            while !text.isEmpty {
                // 拼接“…” + 剩余部分，交给系统自动换行
                let testText = "…" + text
                let attr = makeAttr(testText, font: font)
                let size = bounding(attr)
                
                if size.height <= bounds.height {
                    result = attr
                    break
                }
                text.removeFirst()
            }
            
            self.attributedText = result ?? makeAttr("…", font: font)
        }


    }
    
    private func makeAttr(_ text: String, font: UIFont) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.lineBreakMode = .byCharWrapping
        style.alignment = .center
        
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: textColor ?? .black
        ])
    }
    
    private func bounding(_ attr: NSAttributedString) -> CGSize {
        let rect = attr.boundingRect(
            with: CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return rect.size
    }
    
    /// 单行高度估算
    private func singleLineHeight(fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        return "A".size(withAttributes: [.font: font]).height * lineHeightMultiple * 1.2
    }
    
    // MARK: - Relayout trigger
    override func layoutSubviews() {
        super.layoutSubviews()
        updateText()
    }
}
