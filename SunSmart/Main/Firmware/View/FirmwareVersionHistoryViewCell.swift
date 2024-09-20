//
//  FirmwareVersionHistoryViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/3.
//

import UIKit

class FirmwareVersionHistoryViewCell: UITableViewCell {
    
    private var bgView: UIView!
    private var versionLabel: UILabel!
    private var releaseDateLabel: UILabel!
    private var versionContentLabel: UILabel!
    private var moreBtn: UIButton!
    
    private var maxLines = 5
    
    var firmwareData: FirmwareServerData! {
        didSet {
            versionLabel.text = firmwareData.version
            let timeStr = String.dateConvert(timestamp: "\(firmwareData.releaseDate)", dateFormat: "MMM dd, yyyy")
            releaseDateLabel.text = "\("release_date".localizedString): \(timeStr)"
//            versionContentLabel.text = firmwareData.content
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .left
            paragraphStyle.lineSpacing = SCRYFrom(10)
            paragraphStyle.headIndent = SCRXFrom(8)
            let attStr = NSMutableAttributedString(string: firmwareData.content, attributes: [.paragraphStyle: paragraphStyle])
            versionContentLabel.attributedText = attStr
            updateLayout()
        }
    }
    
    var isExpanded: Bool = false {
        didSet {
            updateLayout()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
     
        selectionStyle = .none
        backgroundColor = .clear
//        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        
//        backgroundColor = .white
//        layer.cornerRadius = SCRYFrom(10)
//        
//        setupUI()
//    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
   
    
    
    /// 更多
    @objc private func moreBtnAction() {
        
    }
 
    private func updateLayout() {
        if isExpanded {
            versionContentLabel.numberOfLines = 0
        } else {
            versionContentLabel.numberOfLines = maxLines
        }
        
        // 判断是否需要显示 "more" 按钮
        moreBtn.isHidden = !isTextTruncated() || isExpanded
        
        if isTextTruncated() && !isExpanded {
            versionContentLabel.snp.updateConstraints { make in
                make.bottom.equalTo(SCRYFrom(-40))
            }
        }else {
            versionContentLabel.snp.updateConstraints { make in
                make.bottom.equalTo(SCRYFrom(-16))
            }
        }
        
    }
    
    private func isTextTruncated() -> Bool {
        guard let detailsText =  versionContentLabel.attributedText else {
            return false
        }
        versionContentLabel.sizeToFit()
        let maxSize = CGSize(width: versionContentLabel.frame.width, height: CGFloat(MAXFLOAT))
//        detailsText.boundingRect(with: <#T##CGSize#>, context: <#T##NSStringDrawingContext?#>)
        let textRect = detailsText.boundingRect(with: maxSize,
                                                options: .usesLineFragmentOrigin,
                                                context: nil)
        // 计算最大高度
        let maxHeight = versionContentLabel.font.lineHeight * CGFloat(maxLines)
        return textRect.height > maxHeight
    }
    
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        bgView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-16))
            make.top.equalToSuperview()
        }
        
        versionLabel = UILabel(text: "1.2.0", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(versionLabel)
        versionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(20))
        }
        
        releaseDateLabel = UILabel(text: "Release date: Jun 22,2024", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(releaseDateLabel)
        releaseDateLabel.snp.makeConstraints { make in
            make.left.equalTo(versionLabel)
            make.top.equalTo(versionLabel.snp.bottom).offset(SCRYFrom(10))
        }
        
        versionContentLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        versionContentLabel.numberOfLines = maxLines
        bgView.addSubview(versionContentLabel)
        versionContentLabel.snp.makeConstraints { make in
//            make.left.equalTo(releaseDateLabel)
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
//            make.width.equalTo(SCRXFrom(303))
//            make.width.equalToSuperview()
            make.top.equalTo(releaseDateLabel.snp.bottom).offset(SCRYFrom(10))
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
        moreBtn = UIButton(title: "more".localizedString, titleSize: 14, titleColor: Bar_Color, target: self, action: #selector(moreBtnAction))
        moreBtn.isUserInteractionEnabled = false
        bgView.addSubview(moreBtn)
        moreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
    }
    
}
