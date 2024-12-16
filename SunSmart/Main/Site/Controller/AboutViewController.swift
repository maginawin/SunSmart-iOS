//
//  AboutViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/22.
//

import UIKit

class AboutViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let tableV = UITableView()
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: 0, right: 0)
        tableV.dataSource = self
        tableV.delegate = self
        tableV.separatorStyle = .none
        tableV.backgroundColor = Background_Color
//        tableV.tableHeaderView = headerView
        return tableV
    }()
    
//    private lazy var headerView: UIView = {
//        let headerV = UIView()
//        headerV.backgroundColor = .white
//        let titleLabel = UILabel(text: "welcome".localizedString, textColor: TextBlack_Color, fontSize: 18)
//        titleLabel.sizeToFit()
//        titleLabel.frame = CGRect(x: SCRXFrom(20), y: SCRYFrom(16), width: self.view.width - SCRXFrom(40), height: titleLabel.height)
//        headerV.addSubview(titleLabel)
//        
//        let messageLabel = UILabel(text: "welcome_message".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
//        messageLabel.numberOfLines = 0
//        let messageSize = messageLabel.sizeThatFits(CGSize(width: titleLabel.width, height: 1000))
//        messageLabel.frame = CGRect(x: titleLabel.x, y: titleLabel.frame.maxY + SCRYFrom(20), width: titleLabel.width, height: messageSize.height)
//        headerV.addSubview(messageLabel)
//        
//        headerV.frame = CGRect(x: 0, y: 0, width: self.view.width, height: messageLabel.frame.maxY + SCRYFrom(28))
//        
//        return headerV
//    }()
    
    private var dataSource: [CustomCellModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "about".localizedString
        view.backgroundColor = Background_Color
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        setupDataSource()
    }
    
    private func setupDataSource() {
        
        let policyModel = CustomCellModel(title: "welcome_privacy_policy".localizedString, style: .arrow)
        
        let serviceModel = CustomCellModel(title: "welcome_policy_use".localizedString, style: .arrow)
        
        dataSource = [policyModel, serviceModel]
    }

}

extension AboutViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let model = dataSource[indexPath.row]
        cell.cellStyle = .arrow
        cell.titleLabel.text = model.title
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.arrowImageView.image = UIImage(named: "arrow_light_right")
        cell.lineView.backgroundColor = Line_Color
        cell.selectionStyle = .none
        cell.backgroundColor = .white
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        var title = ""
        var filePath: String?
        if indexPath.row == 0 {
            title = "welcome_privacy_policy".localizedString
            filePath = Bundle.main.path(forResource: "Privacy Policy", ofType: "html")
        }else {
            title = "welcome_policy_use".localizedString
            filePath = Bundle.main.path(forResource: "User Agreement", ofType: "html")
        }
        if filePath != nil {
            let vc = WebViewController(loadUrl: URL(fileURLWithPath: filePath!), vcTitle: title)
            navigationController?.pushViewController(vc, animated: true)
        }
        
//        var title = ""
//        var attStr: NSMutableAttributedString = .init()
//        
//        let paragraphStyle = NSMutableParagraphStyle()
//        paragraphStyle.lineSpacing = 3
//        paragraphStyle.paragraphSpacing = 8
//        
//        if indexPath.row == 0 {
//            title = "welcome_privacy_policy".localizedString
//            let privacyPolicy = NSMutableAttributedString(string: "protocol_privacy_policy_message".localizedString, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .light)])
//            privacyPolicy.addAttributes([.font: FONTS(15)], range: NSRange(location: 0, length: title.count))
//            privacyPolicy.addAttributes([.font: UIFont.systemFont(ofSize: 15, weight: .light)], range: (privacyPolicy.string as NSString).range(of: "sunsmart_application".localizedString))
//            attStr = privacyPolicy
//            
//        }else {
//            title = "welcome_policy_use".localizedString
//            let termsOfUse = NSMutableAttributedString(string: "protocol_terms_of_use_message".localizedString, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .light)])
//            termsOfUse.addAttributes([.font: FONTS(15)], range: NSRange(location: 0, length: title.count))
//            
//            attStr = termsOfUse
//        }
//        
//      
//        attStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attStr.string.count))
//        
//        
//        let vc = AttributedTextViewController(vcTitle: title, attributedStr: attStr)
//        navigationController?.pushViewController(vc, animated: true)
    }
    
}
