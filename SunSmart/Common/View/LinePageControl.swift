//
//  LinePageControl.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/13.
//

import UIKit

class LinePageControl: UIView {

   
    private var progressView: UIView!
    
    /// 单个page时隐藏分页条
    var hidesForSinglePage: Bool = false {
        didSet {
            updatePageState()
        }
    }
    
    
    var progressColor: UIColor = RGB(102, 103, 171) {
        didSet {
            progressView.backgroundColor = progressColor
        }
    }
    
    var trackColor: UIColor = RGB(216, 216, 216) {
        didSet {
            backgroundColor = trackColor
        }
    }
    
    var cornerRadius: CGFloat = 2 {
        didSet {
            layer.cornerRadius = cornerRadius
        }
    }
    
    var numberOfPages: Int = 0 {
        didSet {
            
            let progressW = frame.size.width / CGFloat(numberOfPages)
            if progressView.width != progressW {
                progressView.width = progressW
                setCurrentPage(currentPage, animated: false)
            }
            if hidesForSinglePage {
                updatePageState()
            }
            
        }
    }
    
    var currentPage: Int {
        get {
            guard self.frame != CGRectZero, numberOfPages > 0 else {
                return 0
            }
             return Int((progressView.x / self.frame.size.width) * Double(numberOfPages))
        }
        set {
            guard currentPage != newValue else {
                return
            }
            setCurrentPage(newValue, animated: false)
            updatePageState()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = trackColor
        self.layer.cornerRadius = cornerRadius
//        self.clipsToBounds = true
        
//        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureAction))
//        self.addGestureRecognizer(panGesture)
        
        progressView = UIView(frame: CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height))
        progressView.backgroundColor = progressColor
        progressView.layer.cornerRadius = cornerRadius
        addSubview(progressView)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let progressW = frame.size.width / CGFloat(numberOfPages)
        progressView.width = progressW
        progressView.height = frame.size.height
        
        setCurrentPage(currentPage, animated: false)
        
        if hidesForSinglePage {
            updatePageState()
        }
    }
    
    @objc private func panGestureAction(sender: UIPanGestureRecognizer) {
        
        switch sender.state {
        case .began:
            self.transform = .init(scaleX: 1.5, y: 1.5)
        case .changed:
            let point = sender.velocity(in: self)
            print(point)
            
            
        case .ended:
            self.transform = .identity
        default:
            break
        }
        
        
    }
    
    /// 设置当前页码
    /// - Parameters:
    ///   - page: 当前页码
    ///   - animated: 是否动画
    func setCurrentPage(_ page: Int, animated: Bool) {
        
        let offsetX = min(progressView.width * CGFloat(page), self.frame.size.width - progressView.width)
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.progressView.x = offsetX
            }
        }else {
            progressView.x = offsetX
        }
    }
    
    private func updatePageState() {
        
        if numberOfPages <= 1 {
            self.isHidden = true
        }else {
            self.isHidden = false
        }
    }
    
}
