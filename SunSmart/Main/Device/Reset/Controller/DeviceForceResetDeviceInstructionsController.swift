//
//  DeviceForceResetDeviceInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/16.
//

import UIKit

class DeviceForceResetDeviceInstructionsController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var contentLabel: UILabel!
    private var flashlightLabel: UILabel!
    private var flashlightImageView: UIImageView!
    private var motionLabel: UILabel!
    private var motionImageView: UIImageView!
    private var meshNetworkLabel: UILabel!
    private var meshNetworkImageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "force_reset_the_device".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(closeAction))
        
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    @objc private func closeAction() {
        
        dismiss(animated: true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
//        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        
        let attStr1 = NSMutableAttributedString(string: "force_reset_instructions_1".localizedString + "\n", attributes: [.paragraphStyle: style])
        
        let attStr2 = NSMutableAttributedString(string: "force_reset_instructions_2".localizedString + "\n", attributes: [.paragraphStyle: style])
        
        let forExampleStr = "for_example:".localizedString
        attStr2.addAttributes([.foregroundColor: SubText_Color], range: NSMakeRange(forExampleStr.count, attStr2.length - forExampleStr.count))
        
        let attStr3 = NSMutableAttributedString(string: "force_reset_instructions_3".localizedString, attributes: [.paragraphStyle: style])
        attStr3.addAttribute(.font, value: UIFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: "note:".localizedString.count))
        
        let contentAttStr = NSMutableAttributedString()
        contentAttStr.append(attStr1)
        contentAttStr.append(attStr2)
        contentAttStr.append(attStr3)
        
        contentLabel = UILabel(text: nil, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        contentLabel.attributedText = contentAttStr
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.top.equalTo(SCRYFrom(6))
        }
        
        flashlightLabel = UILabel(text: "based_on_flashlight".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(flashlightLabel)
        flashlightLabel.snp.makeConstraints { make in
            make.left.equalTo(contentLabel)
            make.top.equalTo(contentLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        flashlightImageView = UIImageView(image: UIImage(named: "device_reset_flashlight"))
        contentView.addSubview(flashlightImageView)
        flashlightImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(isIPad ? 100 : 32))
            make.right.equalTo(SCRXFrom(isIPad ? -100 : -32))
            make.height.equalTo(flashlightImageView.snp.width).multipliedBy(170 / 311.0)
            
            make.top.equalTo(flashlightLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        motionLabel = UILabel(text: "based_on_motion".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(motionLabel)
        motionLabel.snp.makeConstraints { make in
            make.left.equalTo(flashlightLabel)
            make.top.equalTo(flashlightImageView.snp.bottom).offset(SCRYFrom(32))
        }
        
        motionImageView = UIImageView(image: UIImage(named: "device_reset_motion"))
        contentView.addSubview(motionImageView)
        motionImageView.snp.makeConstraints { make in
            make.left.right.equalTo(flashlightImageView)
            make.height.equalTo(flashlightImageView.snp.width).multipliedBy(170 / 311.0)
            make.top.equalTo(motionLabel.snp.bottom).offset(SCRYFrom(24))
        }
     
        meshNetworkLabel = UILabel(text: "based_on_mesh_network".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(meshNetworkLabel)
        meshNetworkLabel.snp.makeConstraints { make in
            make.left.equalTo(motionLabel)
            make.top.equalTo(motionImageView.snp.bottom).offset(SCRYFrom(32))
        }
        
        meshNetworkImageView = UIImageView(image: UIImage(named: "device_reset_network"))
        contentView.addSubview(meshNetworkImageView)
        meshNetworkImageView.snp.makeConstraints { make in
            make.left.right.equalTo(motionImageView)
            make.height.equalTo(meshNetworkImageView.snp.width).multipliedBy(170 / 311.0)
            make.top.equalTo(meshNetworkLabel.snp.bottom).offset(SCRYFrom(24))
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
    }
   

}
