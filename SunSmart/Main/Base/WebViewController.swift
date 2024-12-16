//
//  WebViewController.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/9.
//

import UIKit
import WebKit

class WebViewController: UIViewController {

    private var wkWebView : WKWebView!
    public var loadUrl : URL?
    public var vcTitle : String?
    
    lazy var progressView : UIProgressView = {
        
        let progressV = UIProgressView(frame: CGRect.init(x: 0, y: 0, width: SCREEN_WIDTH, height: 5))
        progressV.progressTintColor = Bar_Color
        progressV.trackTintColor = White_Color
        self.wkWebView.addSubview(progressV)
        return progressV
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = vcTitle
        view.backgroundColor = Background_Color
        
        wkWebView = WKWebView()
        wkWebView.navigationDelegate = self
        wkWebView.allowsBackForwardNavigationGestures = true
        self.view.addSubview(wkWebView)
        wkWebView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
        
        if let url = self.loadUrl {
            if url.isFileURL {
                wkWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }else {
                wkWebView.load(URLRequest(url: url))
            }
        }
        
    }
    
    
    init(loadUrl: URL?, vcTitle: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.loadUrl = loadUrl
        self.vcTitle = vcTitle
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        wkWebView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        wkWebView.removeObserver(self, forKeyPath: "estimatedProgress")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        let progress = change![NSKeyValueChangeKey.newKey] as! Double
        self.progressView.progress = Float(progress)
    }
    
    
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        
        self.progressView.isHidden = false
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//        self.navigationController?.navigationBar.shadowImage = nil
        self.title = self.title ?? webView.title
        self.progressView.isHidden = true
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.progressView.isHidden = true
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if navigationAction.navigationType.rawValue == 0, let linkURLStr = navigationAction.request.url?.absoluteString, (linkURLStr.contains("http") || linkURLStr.contains(".com")) { // 拦截webview内部跳转链接
            decisionHandler(.cancel)
        }else {
            decisionHandler(.allow)
        }
        
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
    
}
