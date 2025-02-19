//
//  FirmwareVersionViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/3.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class FirmwareVersionViewController: UIViewController {

    /// 头部
    private var headerView: UIView!
    private var cloudImageView: UIImageView!
    private var stateLabel: UILabel!
    private var reloadBtn: UIButton!
    
    /// 版本描述
    private var versionScrollView: UIScrollView!
    private var versionContentView: UIView!
    private var newVersionLabel: UILabel!
    private var versionDescribeLabel: UILabel!
    
    /// 缓存版本
    private var cacheVersionView: UIView!
    private var currentVersionTitleLabel: UILabel!
    private var currentVersionLabel: UILabel!
    private var versionDeleteBtn: UIButton!
    
    /// 下载
    private var bottomView: UIView!
    private var downloadBtn: UIButton!
    
    /// 最新的固件数据
//    private var newFirmwareData: FirmwareData?
    
    let type: FirmwareUpdateTypeData
    
    /// 当前设备类型缓存固件数据
    var localFirmwareData: FirmwareData?
    /// 更新本地固件缓存回调
    var updateLocalFirmwareDataCallback: ((FirmwareData?)->Void)?
    
    init(type: FirmwareUpdateTypeData) {
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "firmware_version".localizedString
        view.backgroundColor = Background_Color
        
        #if DEBUG
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: UIButton(normalImageName: "firmware_history", target: self, action: #selector(history))),
            UIBarButtonItem(customView: UIButton(normalImageName: "import", target: self, action: #selector(importFirmwareData)))
        ]
        #else
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "firmware_history")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(history))
        #endif
        
        loadCloudFirmwareRequest()
        
//        updateUI()
    }
    
    /// 获取云端固件
    private func loadCloudFirmwareRequest() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        NetworkRequest.shared.request(.firmwareLatestVersion(deviceType: type.productId.hex)) {[weak self] result in
            guard let self = self else { return }
            XWHUDManager.hideInView(with: self.view)
            if self.headerView == nil {
                self.setupUI()
            }
            switch result {
            case .success(let response):
                let data = JSON(response)["data"]
                guard let version = data["version"].string,
                      let companyId = data["manufacturerId"].string,
                      let customId = data["customerId"].string,
                      let url = data["url"].string,
                      var releaseDate = data["releaseDate"].string,
                      let size = data["size"].int,
                      let deviceTypeStr = data["deviceType"].string, let pid = UInt16(hex: deviceTypeStr.replacingOccurrences(of: "0x", with: "")), pid == self.type.productId else {
                    self.updateUI()
                    return
                }
                
            
                releaseDate = releaseDate.replacingOccurrences(of: "T", with: " ")
                releaseDate = releaseDate.replacingOccurrences(of: "Z", with: "")
                let timeInterval = String.dateConvert(timeStr: releaseDate, dateFormat: nil)
                
                let serverData = FirmwareServerData(productId: pid, version: version.replacingOccurrences(of: "v", with: ""), companyId: UInt16(companyId) ?? 0x0A78, customId: UInt16(customId) ?? 0, url: url, filename: data["filename"].stringValue, size: size, releaseDate: timeInterval, content: data["describe"].stringValue)
                self.type.serverData = serverData
                self.updateUI()
                
            case .failure(_):
                self.updateUI()
            }
        }
        
    }
    
    /// 导入固件包
    @objc private func importFirmwareData() {
        
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.content"], in: .import)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
        
    }
    
    /// 固件版本历史记录
    @objc private func history() {
        let vc = FirmwareVersionHistoryController(productId: self.type.productId)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 删除本地缓存固件
    @objc private func versionDeleteBtnAction() {
        self.localFirmwareData?.delete()
        self.localFirmwareData = nil
        updateLocalFirmwareDataCallback?(self.localFirmwareData)
        
        updateUI()
    }
    
    /// 下载固件
    @objc private func downloadBtnAction() {
        
        guard let serverData = type.serverData, let downloadURL = URL(string: serverData.url)  else { return }
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        ZipHandler.downloadAndHandleZip(from: downloadURL) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let zipData):
                
                let imageSize = UInt32(zipData.firmwareData.count)
                var incomingFirmwareMetadata = Data(bytes: zipData.firmwareId.bytes, count: zipData.firmwareId.count + 3 + 1 + 4 + 2 + 1)
                incomingFirmwareMetadata.writeBits(value: imageSize, numBits: 24, atOffset: 64)
                incomingFirmwareMetadata.writeBits(value: UInt8(zipData.coreType), numBits: 8, atOffset: 88)
                incomingFirmwareMetadata.writeBits(value: UInt32(data: zipData.compositionHash), numBits: 32, atOffset: 96)
                incomingFirmwareMetadata.writeBits(value: UInt16(zipData.elementCount), numBits: 16, atOffset: 128)
                incomingFirmwareMetadata.writeBits(value: UInt8(zipData.test ? 1 : 0), numBits: 1, atOffset: 144)
                incomingFirmwareMetadata.writeBits(value: UInt8(zipData.versionCheck ? 1 : 0), numBits: 1, atOffset: 145)
                
                self.localFirmwareData = .init(name: serverData.filename, version: serverData.version, firmwareID: zipData.firmwareId, data: zipData.firmwareData, updateFirmwareImageIndex: zipData.imageIndex, incomingFirmwareMetadata: incomingFirmwareMetadata, productId: serverData.productId, vendorId: serverData.companyId, customId: serverData.customId, releaseDate: serverData.releaseDate, content: serverData.content, compositionHash: zipData.compositionHash.reversed().toHexString())
                self.localFirmwareData?.save()
                self.updateLocalFirmwareDataCallback?(self.localFirmwareData)
                self.updateUI()
                
            case .failure(_):
                XWHUDManager.showErrorTipHUD("download_failure".localizedString)
            }
        }
        
    }
    
    /// 刷新数据
    @objc private func reloadBtnAction() {
        // 重新获取线上版本
        loadCloudFirmwareRequest()
    }
    
    private func updateUI() {
        
        
        if let version = self.localFirmwareData?.version {
            self.currentVersionLabel.text = version
            self.versionDeleteBtn.isHidden = false
            self.currentVersionLabel.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-64))
            }
        }else {
            self.currentVersionLabel.text = "none".localizedString
            self.versionDeleteBtn.isHidden = true
            self.currentVersionLabel.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-20))
            }
        }
        
        if let newFirmwareData = self.type.serverData {
            
//            if let currentFirmwareData = self.localFirmwareData {
                // 有新版本
                if self.localFirmwareData == nil || newFirmwareData.version.compare(self.localFirmwareData!.version, options: .numeric) == .orderedDescending {
                    
                    stateLabel.text = "new_version_found".localizedString
                    
                    let sizeStr = String(format: "%.1fKB", Float(newFirmwareData.size) / 1000.0)
                    let time = "\("release_date".localizedString): \(String.dateConvert(timestamp: "\(newFirmwareData.releaseDate)", dateFormat: "MMM dd, yyyy"))"
                    let versionDesc = newFirmwareData.content
                    let content = "\(newFirmwareData.version)\n\(sizeStr)\n\(time)\n\(versionDesc)"
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineSpacing = 10
                    paragraphStyle.headIndent = 8
                    
                    let attStr = NSMutableAttributedString(string: content, attributes: [.paragraphStyle: paragraphStyle])
                    attStr.addAttribute(.foregroundColor, value: SubText_Color, range: (content as NSString).range(of: versionDesc))
                    versionDescribeLabel.attributedText = attStr
                    
                    versionScrollView.isHidden = false
                    cacheVersionView.snp.remakeConstraints { make in
                        make.left.equalTo(SCRXFrom(16))
                        make.right.equalTo(SCRXFrom(-16))
                        make.top.equalTo(versionScrollView.snp.bottom).offset(SCRYFit(18))
                        make.height.equalTo(SCRYFit(52))
                    }
                    downloadBtn.isEnabled = true
                }else { // 已是最新版本
                    stateLabel.text = "the_latest_version".localizedString
                    versionScrollView.isHidden = true
                    cacheVersionView.snp.remakeConstraints { make in
                        make.left.equalTo(SCRXFrom(16))
                        make.right.equalTo(SCRXFrom(-16))
                        make.top.equalTo(versionScrollView)
                        make.height.equalTo(SCRYFit(52))
                    }
                    downloadBtn.isEnabled = false
                }
//            }
            stateLabel.isHidden = false
            reloadBtn.isHidden = true
        }else {
            stateLabel.isHidden = true
            versionDescribeLabel.attributedText = NSAttributedString(string: "network_error".localizedString)
            reloadBtn.isHidden = false
            downloadBtn.isEnabled = false
            versionScrollView.isHidden = false
            cacheVersionView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(versionScrollView.snp.bottom).offset(SCRYFit(18))
                make.height.equalTo(SCRYFit(52))
            }
        }
        
        
        
        
    }
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.height.equalTo(SCRYFit(147))
        }
        
        cloudImageView = UIImageView(image: UIImage(named: "firmware_cloud_version"))
        headerView.addSubview(cloudImageView)
        cloudImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFit(25))
        }
        
        stateLabel = UILabel(text: "new_version_found".localizedString, textColor: SubText_Color, fontSize: 15)
        stateLabel.textAlignment = .center
        headerView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(cloudImageView.snp.bottom).offset(SCRYFit(12))
        }
        
        reloadBtn = UIButton(normalImageName: "refresh", target: self, action: #selector(reloadBtnAction))
        reloadBtn.isHidden = true
        headerView.addSubview(reloadBtn)
        reloadBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(cloudImageView.snp.bottom).offset(SCRYFit(10))
        }
        
        versionScrollView = UIScrollView()
        versionScrollView.backgroundColor = .white
        versionScrollView.layer.cornerRadius = SCRYFrom(10)
//        versionScrollView.showsVerticalScrollIndicator = false
        view.addSubview(versionScrollView)
        versionScrollView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(headerView.snp.bottom)
            make.height.equalTo(SCRYFit(236))
        }
        
        versionContentView = UIView()
        versionScrollView.addSubview(versionContentView)
        versionContentView.snp.makeConstraints { make in
            make.width.edges.equalToSuperview()
        }
        
        newVersionLabel = UILabel(text: "new_version".localizedString, textColor: TextBlack_Color, fontSize: 14)
        versionContentView.addSubview(newVersionLabel)
        newVersionLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFit(16))
            make.left.equalTo(SCRXFrom(20))
        }
        
        versionDescribeLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        versionDescribeLabel.numberOfLines = 0
        versionContentView.addSubview(versionDescribeLabel)
        versionDescribeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(newVersionLabel.snp.bottom).offset(SCRYFit(11))
            make.bottom.equalTo(SCRYFit(-16)).priority(.low)
        }
        
        cacheVersionView = UIView()
        cacheVersionView.backgroundColor = .white
        cacheVersionView.layer.cornerRadius = SCRYFrom(10)
        view.addSubview(cacheVersionView)
        cacheVersionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(versionScrollView.snp.bottom).offset(SCRYFit(18))
            make.height.equalTo(SCRYFit(52))
        }
        
        currentVersionTitleLabel = UILabel(text: "current_target_version".localizedString, textColor: TextBlack_Color, fontSize: 14)
        cacheVersionView.addSubview(currentVersionTitleLabel)
        currentVersionTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
        }
        
        currentVersionLabel = UILabel(text: "1.1.0", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        cacheVersionView.addSubview(currentVersionLabel)
        currentVersionLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-64))
            make.centerY.equalToSuperview()
        }
        
        versionDeleteBtn = UIButton(normalImageName: "firmware_delete", target: self, action: #selector(versionDeleteBtnAction))
        cacheVersionView.addSubview(versionDeleteBtn)
        versionDeleteBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFit(56))
        }
        
        downloadBtn = UIButton(title: "Download".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(downloadBtnAction))
        downloadBtn.setTitleColor(RGB(148, 163, 184), for: .disabled)
        bottomView.addSubview(downloadBtn)
        downloadBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFit(56))
        }
    }

}

extension FirmwareVersionViewController: UIDocumentPickerDelegate {
    
    /// 选择文件导入回调
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, url.absoluteString.contains(".zip") else { return }
        do {
            let data = try Data(contentsOf: url)
            let zipData = try ZipHandler.handleZipData(data)
            let imageSize = UInt32(zipData.firmwareData.count)
            var incomingFirmwareMetadata = Data(bytes: zipData.firmwareId.bytes, count: zipData.firmwareId.count + 3 + 1 + 4 + 2 + 1)
            incomingFirmwareMetadata.writeBits(value: imageSize, numBits: 24, atOffset: 64)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.coreType), numBits: 8, atOffset: 88)
            incomingFirmwareMetadata.writeBits(value: UInt32(data: zipData.compositionHash), numBits: 32, atOffset: 96)
            incomingFirmwareMetadata.writeBits(value: UInt16(zipData.elementCount), numBits: 16, atOffset: 128)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.test ? 1 : 0), numBits: 1, atOffset: 144)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.versionCheck ? 1 : 0), numBits: 1, atOffset: 145)
            
            let firmwareData = FirmwareData(name: "", version: zipData.firmwareVersion, firmwareID: zipData.firmwareId, data: zipData.firmwareData, updateFirmwareImageIndex: zipData.imageIndex, incomingFirmwareMetadata: incomingFirmwareMetadata, productId: self.type.productId, vendorId: self.type.serverData?.companyId ?? 0x0A78, customId: self.type.serverData?.customId ?? 0x00, releaseDate: Int64(Date().timeIntervalSince1970), content: "test", compositionHash: zipData.compositionHash.reversed().toHexString())
            firmwareData.save()
            XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
            self.localFirmwareData = firmwareData
            self.updateLocalFirmwareDataCallback?(self.localFirmwareData)
            self.updateUI()
            
        } catch { // 失败提示
            print(error)
            XWHUDManager.showErrorTipHUD("failed".localizedString + "!")
        }
    }
    
}
