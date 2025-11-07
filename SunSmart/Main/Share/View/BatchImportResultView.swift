//
//  BatchImportResultView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/30.
//

import UIKit

class BatchImportResultView: UIView {

    typealias HelpCallback = (()->Void)
    typealias CloseCallback = (()->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var tableView: UITableView!
    private var lineView: UIView!
    private var closeBtn: UIButton!
    
    /// 总计条目
    private var totalItems: [ItemType] = []
//    private var spaces: [ResultState] = [.successfully, .presenceEditor, .presenceEditor, .invalid, .alreadyExist, .successfully, .presenceEditor, .presenceEditor, .invalid, .alreadyExist]
    private let results: [BatchSpaceImportResult]
    
    var helpCallback: HelpCallback?
    var closeCallback: CloseCallback?
    
    init(results: [BatchSpaceImportResult] ,helpCallback: HelpCallback? = nil, closeCallback: CloseCallback?) {
        
        self.results = results
        super.init(frame: UIScreen.main.bounds)
        self.helpCallback = helpCallback
        self.closeCallback = closeCallback
        
        let total = results.count
        let successfullyCount = results.filter({ $0.status == .successfully }).count
        let presenceEditorCount = results.filter({ $0.status == .presenceEditor }).count
        let invalidCount = results.filter({ $0.status == .invalid }).count
        let alreadyExistCount = results.filter({ $0.status == .alreadyExist }).count
        
        self.totalItems = [
            .total(count: total),
            .successfully(count: successfullyCount),
            .presenceEditor(count: presenceEditorCount),
            .invalid(count: invalidCount),
            .alreadyExist(count: alreadyExistCount)
        ]
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        } completion: { _ in
            if self.tableView.firstShowFlashScrollIndicators {
                self.tableView.flashScrollIndicatorsIfNeeded()
            }
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func close() {
        closeCallback?()
        hide()
    }
    
    @objc private func helpBtnAction() {
        helpCallback?()
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(20)
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "batch_import_results".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        contentView.addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        closeBtn = UIButton(title: "CLOSE".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(close))
        contentView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(0, 0, 0, 0.03)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
            make.bottom.equalTo(closeBtn.snp.top)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(32)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
            make.bottom.equalTo(lineView.snp.top).offset(SCRYFrom(-17))
            let showRows = min(totalItems.count + results.count, 10)
            make.height.equalTo(CGFloat(showRows) * tableView.rowHeight + SCRYFrom(41))
        }
        
    }
    
}

extension BatchImportResultView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return totalItems.count
        }
        return results.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .none
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.textColor = SubText_Color
        if indexPath.section == 0 {
            let item = totalItems[indexPath.row]
            cell.titleLabel.text = item.data.title
            cell.contentLabel.text = "\(item.data.count)"
        }else {
            let result = results[indexPath.row]
            cell.titleLabel.text = result.spaceName
            cell.contentLabel.text = result.status.rawString
        }
        cell.selectionStyle = .none
        cell.lineView.isHidden = true
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else {
            return nil
        }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SyncDevicesTitleHeaderView
        headerView.titleLabel.text = "detailed_informations".localizedString
        headerView.titleLabel.textColor = Title_Color
        headerView.titleLeftMargin = SCRXFrom(16)
        headerView.contentView.backgroundColor = .clear
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 1 {
            return SCRYFrom(41)
        }
        return 0
    }
}

extension BatchImportResultView {
    
    enum ItemType {
        
        var data: (title: String, count: Int) {
            switch self {
            case .total(let count):
                return ("total_import_attempts".localizedString + ":", count)
            case .successfully(let count):
                return ("successfully_improrted".localizedString + ":", count)
            case .presenceEditor(let count):
                return ("presence_editor".localizedString + ":", count)
            case .invalid(let count):
                return ("invalid".localizedString + ":", count)
            case .alreadyExist(let count):
                return ("already_exist".localizedString + ":", count)
            }
        }
        
        /// 总计
        case total(count: Int)
        /// 成功导入数量
        case successfully(count: Int)
        /// 存在管理员空间数量
        case presenceEditor(count: Int)
        /// 空间失效数量
        case invalid(count: Int)
        /// 已存在空间数量
        case alreadyExist(count: Int)
    }
}
