//
//  LBXScanViewController.swift
//  swiftScan
//
//  Created by lbxia on 15/12/8.
//  Copyright © 2015年 xialibing. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation

public protocol LBXScanViewControllerDelegate: class {
     func scanFinished(scanResult: LBXScanResult, error: String?)
}

public protocol QRRectDelegate {
    func drawwed()
}

open class LBXScanViewController: UIViewController {
    
    // 返回扫码结果，也可以通过继承本控制器，改写该handleCodeResult方法即可
    open weak var scanResultDelegate: LBXScanViewControllerDelegate?

    open var delegate: QRRectDelegate?

    open var scanObj: LBXScanWrapper?

    open var scanStyle: LBXScanViewStyle? = LBXScanViewStyle()

    open var qRScanView: LBXScanView?

    // 启动区域识别功能
    open var isOpenInterestRect = false
    
    //连续扫码
    open var isSupportContinuous = false;
    // 扫码完成后退出页面
    open var scanFineshedExit: Bool = true

    // 识别码的类型
    public var arrayCodeType: [AVMetadataObject.ObjectType]?

    // 是否需要识别后的当前图像
    public var isNeedCodeImage = false
    
    // 描述
    public var message: String?

    // 相机启动提示文字
    public var readyString: String! = "loading"
    // 返回按钮
    private var backBtn: UIButton!
    // 描述
    private var messageLabel: UILabel!
    // 手电筒
    private var flashlightBtn: UIButton!
    // 相册
    private var photoAlbumBtn: UIButton!
    // 分割线
    private var lineView: UIView!
    
    open override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.

        // [self.view addSubview:_qRScanView];
        view.backgroundColor = UIColor.black
        edgesForExtendedLayout = UIRectEdge(rawValue: 0)
        
        backBtn = UIButton()
        backBtn.setImage(UIImage(named: "navigation_back")?.withTintColor(.white), for: .normal)
        backBtn.addTarget(self, action: #selector(backAction), for: .touchUpInside)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backBtn)
        
        messageLabel = UILabel()
        messageLabel.font = UIFont.systemFont(ofSize: 15, weight: .light)
        messageLabel.text = message ?? "scan_qrcode_message".localizedString
        messageLabel.numberOfLines = 2
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        
        flashlightBtn = UIButton()
        flashlightBtn.setImage(UIImage(named: "flashlight"), for: .normal)
        flashlightBtn.addTarget(self, action: #selector(flashlight), for: .touchUpInside)
        flashlightBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flashlightBtn)
        
        photoAlbumBtn = UIButton()
        photoAlbumBtn.setImage(UIImage(named: "photo_album"), for: .normal)
        photoAlbumBtn.translatesAutoresizingMaskIntoConstraints = false
        photoAlbumBtn.addTarget(self, action: #selector(openPhotoAlbum), for: .touchUpInside)
        view.addSubview(photoAlbumBtn)
        
        lineView = UIView()
        lineView.backgroundColor = RGB(255, 255, 255, 0.5)
        lineView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lineView)
        
        
        let statusBarManager = UIApplication.shared.windows.first!.windowScene!.statusBarManager!
        
        NSLayoutConstraint.activate([
            backBtn.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
            backBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: statusBarManager.statusBarFrame.height),
            backBtn.widthAnchor.constraint(equalToConstant: 30),
            backBtn.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        let scanRect = LBXScanView.getScanRectWithPreView(preView: view, style: scanStyle!)
        let scanMaxY = view.height * (scanRect.minY + scanRect.width) + (presentingViewController == nil ? kSafeAreaTopHeight : 0)
        
        NSLayoutConstraint.activate([
            messageLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 35),
            messageLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -35),
            messageLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: scanMaxY + SCRYFit(56))
        ])
        
        NSLayoutConstraint.activate([
            flashlightBtn.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 56),
            flashlightBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -SCRYFit(44) - kSafeAreaBottomHeight),
        ])
        
        NSLayoutConstraint.activate([
            photoAlbumBtn.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -56),
            photoAlbumBtn.centerYAnchor.constraint(equalTo: flashlightBtn.centerYAnchor)
        ])
        
        NSLayoutConstraint.activate([
            lineView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lineView.centerYAnchor.constraint(equalTo: flashlightBtn.centerYAnchor),
            lineView.widthAnchor.constraint(equalToConstant: 1),
            lineView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
    }

    @objc private func backAction() {
        navigationController?.popViewController(animated: true)
    }
    
    open func setNeedCodeImage(needCodeImg: Bool) {
        isNeedCodeImage = needCodeImg
    }

    // 设置框内识别
    open func setOpenInterestRect(isOpen: Bool) {
        isOpenInterestRect = isOpen
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        drawScanView()
        perform(#selector(LBXScanViewController.startScan), with: nil, afterDelay: 0.3)
    }
    
    open override var prefersStatusBarHidden: Bool {
        return true
    }

    @objc open func startScan() {
        if scanObj == nil {
            var cropRect = CGRect.zero
            if isOpenInterestRect {
                cropRect = LBXScanView.getScanRectWithPreView(preView: view, style: scanStyle!)
            }

            // 指定识别几种码
            if arrayCodeType == nil {
                arrayCodeType = [AVMetadataObject.ObjectType.qr as NSString,
                                 AVMetadataObject.ObjectType.ean13 as NSString,
                                 AVMetadataObject.ObjectType.code128 as NSString] as [AVMetadataObject.ObjectType]
            }

            scanObj = LBXScanWrapper(videoPreView: view,
                                     objType: arrayCodeType!,
                                     isCaptureImg: isNeedCodeImage,
                                     cropRect: cropRect,
                                     success: { [weak self] (arrayResult) -> Void in
                                        guard let strongSelf = self else {
                                            return
                                        }
                                        if !strongSelf.isSupportContinuous {
                                            // 停止扫描动画
                                            strongSelf.qRScanView?.stopScanAnimation()
                                        }
                                        strongSelf.handleCodeResult(arrayResult: arrayResult)
                                        strongSelf.scanObj?.setTorch(torch: false)
                                     })
        }
        
        scanObj?.supportContinuous = isSupportContinuous;

        // 结束相机等待提示
        qRScanView?.deviceStopReadying()

        // 开始扫描动画
        qRScanView?.startScanAnimation()

        // 相机运行
        scanObj?.start()
    }
    
    open func drawScanView() {
        if qRScanView == nil {
            qRScanView = LBXScanView(frame: view.frame, vstyle: scanStyle!)
            view.addSubview(qRScanView!)
            delegate?.drawwed()
            
            view.sendSubviewToBack(qRScanView!)
//            view.bringSubviewToFront(backBtn)
//            view.bringSubviewToFront(titleLabel)
        }
        qRScanView?.deviceStartReadying(readyStr: readyString)
    }
   

    /**
     处理扫码结果，如果是继承本控制器的，可以重写该方法,作出相应地处理，或者设置delegate作出相应处理
     */
    open func handleCodeResult(arrayResult: [LBXScanResult]) {
        guard let delegate = scanResultDelegate else {
            fatalError("you must set scanResultDelegate or override this method without super keyword")
        }
        //  !isSupportContinuous
        if scanFineshedExit {
            navigationController?.popViewController(animated: true)

        }
        
        if let result = arrayResult.first {
            delegate.scanFinished(scanResult: result, error: nil)
        } else {
            let result = LBXScanResult(str: nil, img: nil, barCodeType: nil, corner: nil)
            delegate.scanFinished(scanResult: result, error: "no scan result")
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        qRScanView?.stopScanAnimation()
        scanObj?.stop()
        
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    @objc private func flashlight(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        scanObj?.setTorch(torch: sender.isSelected)
    }
    
    @objc open func openPhotoAlbum() {
        LBXPermissions.authorizePhotoWith { [weak self] _ in
            let picker = UIImagePickerController()
            picker.sourceType = UIImagePickerController.SourceType.photoLibrary
            picker.delegate = self
            picker.allowsEditing = true
            self?.present(picker, animated: true, completion: nil)
        }
    }
}

//MARK: - 图片选择代理方法
extension LBXScanViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    //MARK: -----相册选择图片识别二维码 （条形码没有找到系统方法）
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage
        let originalImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
        guard let image = editedImage ?? originalImage else {
            showMsg(title: nil, message: NSLocalizedString("Identify failed", comment: "Identify failed"))
            return
        }
        let arrayResult = LBXScanWrapper.recognizeQRImage(image: image)
        if !arrayResult.isEmpty {
            handleCodeResult(arrayResult: arrayResult)
        }
    }
    
}

//MARK: - 私有方法
private extension LBXScanViewController {
    
    func showMsg(title: String?, message: String?) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let alertAction = UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default, handler: nil)
        alertController.addAction(alertAction)
        present(alertController, animated: true, completion: nil)
    }
    
}
