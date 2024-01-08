//
//  CustomProgressView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/25.
//

import UIKit

class CustomProgressView: UIView {

    var progressView: UIView!
    
    var trackColor: UIColor = RGB(30, 35, 41, 0.1) {
        didSet {
            backgroundColor = trackColor
        }
    }
    
    var progressColor: UIColor = RGB(244, 206, 152) {
        didSet {
            progressView.backgroundColor = progressColor
            
        }
    }
    
    var cornerRadius: CGFloat = 2 {
        didSet {
            layer.cornerRadius = cornerRadius
            progressView.layer.cornerRadius = cornerRadius
        }
    }
    
    /// 进度 0~100
    var progress: Int = 0 {
        didSet {
//            guard progress != newValue else {
//                return
//            }
            setProgress(progress, animated: false)
        }
       
//        get {
//            guard self.frame != CGRectZero else {
//                return 0
//            }
//            return Int((progressView.width / self.frame.size.width) * 100.0)
//        }set {
//            guard progress != newValue else {
//                return
//            }
//            setProgress(newValue, animated: false)
//        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = trackColor
        layer.cornerRadius = cornerRadius
        
        progressView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: frame.size.height))
        progressView.backgroundColor = progressColor
        progressView.layer.cornerRadius = cornerRadius
        addSubview(progressView)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let progressW = self.frame.size.width * CGFloat(progress) / 100.0
        progressView.width = progressW
        progressView.height = frame.size.height
        
    }
    
    /// 设置当前进度
    /// - Parameters:
    ///   - progress: 0~100
    ///   - animated: 是否动画
    func setProgress(_ progress: Int, animated: Bool) {
        
        let value = min(max(progress, 0), 100)
        
        let width = self.frame.size.width * CGFloat(value) / 100.0
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.progressView.width = width
            }
        }else {
            progressView.width = width
        }
        
        if progress != self.progress {
            self.progress = progress
        }
    }

}
