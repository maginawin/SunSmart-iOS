//
//  SceneGroupsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/25.
//

import UIKit
import NordicSigMeshSDK

class SceneGroupsViewCell: UICollectionViewCell {
    
    var bgView: UIView!
    var iconImageView: UIImageView!
    var imageLabel: UILabel!
    var nameLabel: AdaptiveTextView!
    var progressView: CustomProgressView!
    var syncFailImageView: UIImageView!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更新数据
    /// - Parameters:
    ///   - group: 组
    ///   - sceneData: 执行的场景数据
    func updateData(group: Group, sceneData: ExecuteSceneData?) {
        
//        iconImageView.image = UIImage(named: "group_image_\(group.info.imageId)")
        if let text = group.info.imageText, text.count > 0 {
            imageLabel.isHidden = false
            imageLabel.text = text
            iconImageView.isHidden = true
        }else {
            imageLabel.isHidden = true
            iconImageView.isHidden = false
            iconImageView.image = UIImage(named: "group_image_\(group.info.imageId)") //device_light_offline
        }
        
        if group.isOn {
            bgView.backgroundColor = .white
            nameLabel.textColor = Title_Color
        }else {
            bgView.backgroundColor = RGB(226, 226, 226)
            nameLabel.textColor = RGB(148, 163, 184)
        }
        nameLabel.text = group.name
        
        if let data = sceneData {
            let groupLightData = group.info.profile.lightData
            var lightnessValue = data.lightness
            lightnessValue = max(groupLightData.data.lowEndTrim, min(groupLightData.data.highEndTrim, lightnessValue))
            progressView.progress = lightnessValue
//            data.lightness
            // max(groupLightData.data.lowEndTrim, min(groupLightData.data.highEndTrim, <#T##y: Comparable##Comparable#>))
           
            let cct100 = Node.getTemperature100(temperature: UInt16(data.cct), range: SceneExecuteData.cctRange)
            progressView.progressColor = Node.getCctMixColor(temperature100: cct100)
        }
        
//        syncFailImageView.isHidden = !group.nodes.contains(where: {
//            let syncData = $0.getNeedSyncGroupData()
//            return syncData.syncScenes.count > 0 || syncData.deleteScenes.count > 0
//        })
        
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        bgView.layer.cornerRadius = self.width * 0.5
    }
  
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        bgView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        bgView.layer.shadowOffset = CGSize(width: 0,height: 2)
        bgView.layer.shadowOpacity = 1
        bgView.layer.shadowRadius = 4
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(bgView.snp.width)
        }
        
        iconImageView = UIImageView()
        bgView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
//            make.bottom.equalTo(bgView.snp.centerY).offset(SCRYFrom(-3))
            make.centerY.equalToSuperview().offset(SCRYFrom(-8))
//            make.top.equalTo(SCRYFrom(11))
        }
        
        imageLabel = UILabel(text: nil, textColor: RGB(20, 46, 79))
        imageLabel.font = UIFont.systemFont(ofSize: SCRYFrom(36), weight: .thin)
        contentView.addSubview(imageLabel)
        imageLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
//            make.top.equalTo(SCRYFrom(11))
            make.centerY.equalTo(iconImageView)
//            make.bottom.equalTo(bgView.snp.centerY)
//            make.bottom.equalTo(self.snp.centerY)
        }
        
     
        
        nameLabel = AdaptiveTextView()
        nameLabel.textColor = Title_Color
        nameLabel.maxFontSize = FontFit(12)
        nameLabel.minFontSize = FontFit(8.5)
        nameLabel.lineHeightMultiple = 0.9
//        UILabel(text: "Group 1", textColor: Title_Color, fontSize: 12, fontWeight: .light)
//        nameLabel.textAlignment = .center
//        nameLabel.lineBreakMode = .byTruncatingHead
        bgView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.top.equalTo(bgView.snp.bottom).offset(SCRYFrom(-23))
            make.height.equalTo(SCRYFrom(20))
        }
        
        progressView = CustomProgressView()
        progressView.cornerRadius = 2
        progressView.trackColor = RGB(30, 35, 41, 0.1)
        progressView.progressPadding = 0.5
        progressView.progress = 50
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(42))
            make.height.equalTo(4)
            make.bottom.equalTo(SCRYFrom(-2))
        }
        
//        syncFailImageView = UIImageView(image: UIImage(named: "schedule_sync_failed"))
//        syncFailImageView.isHidden = true
//        contentView.addSubview(syncFailImageView)
//        syncFailImageView.snp.makeConstraints { make in
//            make.right.top.equalToSuperview()
//        }
    }
    
}
