//
//  SpaceVisitorListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/3.
//

import UIKit
import SwiftyJSON

class SpaceVisitorListViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var clearSelectBtn: UIButton!
    private lazy var selectAllBtn: UIButton = {
        let btn = UIButton(title: "select_all".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color, fit: false, target: self, action:  #selector(selectAllAction))
        return btn
    }()
    
    let space: SpaceData
    var visitors: [UserData] = []
    
    private var selectVisitors: [UserData] = []
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "visitor_list".localizedString
        view.backgroundColor = Background_Color
        
        selectAllBtn.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: selectAllBtn)
        
        setupTableView()
        
        loadMemberRequest()
    }
    
    /// 获取space成员数据
    private func loadMemberRequest() {

        XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
       
        NetworkRequest.shared.request(.spaceMembers(siteId: self.space.siteId, spaceId: self.space.id)) {[weak self] result in
            guard let self = self else { return }
            XWHUDManager.hideInView(with: self.view)
            
            switch result {
            case .success(let response):
                if let visitorDatas = JSON(response)["data"]["visitors"].arrayObject as? [[String: Any]] {
                    let visitors: [UserData] = visitorDatas.compactMap({
                        if let userId = $0["userId"] as? String, let username = $0["username"] as? String {
                            return UserData(name: username, uuid: userId)
                        }
                        return nil
                    })
                    self.space.visitors = visitors
                    self.space.save()
                }
            case .failure(let error):
                XWHUDManager.showTipHUD(error.localizedDescription, isLineFeed: true)
            }
            
            self.visitors = self.space.visitors
            self.tableView.reloadData()
            self.updateEmptyUI()
        }
        
    }
    
    /// 选中所有
    @objc private func selectAllAction() {
        
        selectVisitors = visitors
        tableView.reloadData()
        clearSelectBtn.isEnabled = selectVisitors.count > 0
    }
    
    /// 清除选中访客（批量删除）
    /// - Parameters force: 是否强制删除
    @objc private func clearSelectBtnAction() {
    
        guard selectVisitors.count > 0 else {
            return
        }
        SRAlertView(title: "notification".localizedString, message: "space_clear_visitors_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            self.deleteVisitorsRequest(visitors: self.selectVisitors)
        })]).show()
        
    }
    
    /// 批量删除访客请求
    /// - Parameters:
    ///   - visitors: 访客list
    ///   - force: 强制删除
    private func deleteVisitorsRequest(visitors: [UserData], force: Bool = false) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.clearSpaceMembers(siteId: space.siteId, spaceId: space.id, userIds: visitors.map({ $0.uuid }), permission: .visitor, force: force)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                // 删除访客结果
                if let detail = JSON(response)["data"]["detail"].dictionaryObject as? [String: Int] {
                    // 删除的访客中正在使用space
                    let usedVisitorIds = detail.filter({ $0.value == NetworkApiError.visitorBeingUsedSpace.code }).map({ $0.key })
                    // 删除成功的访客
                    let successVisitorIds = detail.filter({ $0.value == 1 }).map({ $0.key })
                    
                    // 清空space内删除成功的访客
                    // 删除访客
                    self.space.visitors.removeAll(where: { successVisitorIds.contains($0.uuid) })
                    space.save()
                    
                    self.visitors = self.space.visitors
                    self.selectVisitors.removeAll()
//                    self.selectVisitors.removeAll(where: { successVisitorIds.contains($0.uuid) })
                    // 有正在使用的访客
                    if usedVisitorIds.count > 0 {
                        SRAlertView(title: "notification".localizedString, message: "space_delete_used_visitors_message".localizedString, actions: [SRAlertAction(title: "skip".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                            guard let self = self else { return }
                            self.clearSelectBtn.isEnabled = self.selectVisitors.count > 0
                            self.tableView.reloadData()
                            self.updateEmptyUI()
                            
                        }), SRAlertAction(title: "clear".localizedString, actionHandler: {[weak self] _ in
                            // 强制删除正在使用的访客
                            let forceDeleteUsers = visitors.filter({ usedVisitorIds.contains($0.uuid) })
                            // 强制删除请求
                            self?.deleteVisitorsRequest(visitors: forceDeleteUsers, force: true)
                        })]).show()
                    }else {
                        // 删除成功
                        self.clearSelectBtn.isEnabled = self.selectVisitors.count > 0
                        self.tableView.reloadData()
                        self.updateEmptyUI()
                    }
                }else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 删除访客  force: 是否强制删除，对方正在使用时二次确认
    private func deleteVisitor(_ visitor: UserData, force: Bool) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.clearSpaceMember(siteId: space.siteId, spaceId: space.id, userId: visitor.uuid, permission: .visitor, force: force)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                // 删除访客
                space.visitors.removeAll(where: { $0.uuid == visitor.uuid })
                space.save()
                if let row = self.visitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
                    self.visitors.remove(at: row)
                    self.tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
                }
                if let index = self.selectVisitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
                    self.selectVisitors.remove(at: index)
                }
                self.clearSelectBtn.isEnabled = self.selectVisitors.count > 0
                self.updateEmptyUI()
                
            case .failure(let error): // 是否正在使用space
                if error == .visitorBeingUsedSpace && !force {
                    // 对应访客正在使用space
                    SRAlertView(title: "notification".localizedString, message: "space_delete_visitor_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                        // 强制删除
                        self?.deleteVisitor(visitor, force: true)
                    })]).show()
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
    }
    
    private func updateEmptyUI() {
        
        if visitors.isEmpty {
            if tableView.frame == .zero {
                view.layoutIfNeeded()
            }
            tableView.showEmptyDataView(title: "no_visitors".localizedString)
            selectAllBtn.isHidden = true
            bottomView.isHidden = true
        }else {
            tableView.hideEmptyDataView()
            selectAllBtn.isHidden = false
            bottomView.isHidden = false
        }
        
    }
    
    private func setupTableView() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        bottomView.isHidden = true
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        clearSelectBtn = UIButton(title: "Clear_Visitor".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(clearSelectBtnAction))
        clearSelectBtn.setTitleColor(Message_Color, for: .disabled)
        clearSelectBtn.isEnabled = false
        bottomView.addSubview(clearSelectBtn)
        clearSelectBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(SpaceVisitorListViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = SCRYFrom(44)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(11), left: 0, bottom: SCRYFrom(11), right: 0)
        tableView.backgroundColor = .clear
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0))
            make.bottom.equalTo(bottomView.snp.top)
        }
    }

}

extension SpaceVisitorListViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visitors.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SpaceVisitorListViewCell
        let visitor = visitors[indexPath.row]
        cell.nameLabel.text = visitor.name
        cell.selectImageView.image = UIImage(named: selectVisitors.contains(where: { $0.uuid == visitor.uuid }) ? "device_select" : "device_select_un")
        cell.deleteCallback = {
            // 删除访客
            SRAlertView(title: "notification".localizedString, message: "space_clear_visitor_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                self?.deleteVisitor(visitor, force: false)
            })]).show()
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let visitor = visitors[indexPath.row]
        if let index = selectVisitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
            selectVisitors.remove(at: index)
        }else {
            selectVisitors.append(visitor)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        
        clearSelectBtn.isEnabled = selectVisitors.count > 0
    }
    
}

class SpaceVisitorListViewCell: UITableViewCell {
    
    var nameLabel: UILabel!
    var selectImageView: UIImageView!
    private var deleteBtn: UIButton!
    private var lineView: UIView!
    
    var deleteCallback: (()->Void)?
 
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func deleteBtnAction() {
        deleteCallback?()
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "Jesse's iphone 13", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(8))
            make.width.lessThanOrEqualTo(SCRXFrom(180))
            make.centerY.equalToSuperview()
        }
        
        deleteBtn = UIButton(normalImageName: "visitor_clear", target: self, action: #selector(deleteBtnAction))
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(nameLabel)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
}
