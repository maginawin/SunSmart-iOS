//
//  SpaceVisitorListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/3.
//

import UIKit

class SpaceVisitorListViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var clearSelectBtn: UIButton!
    private lazy var selectAllBtn: UIButton = {
        let btn = UIButton(title: "select_all".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color, fit: false, target: self, action:  #selector(selectAllAction))
        return btn
    }()
    
    let space: SpaceData
    var visitors: [UserData]
    
    private var selectVisitors: [UserData] = []
    
    init(space: SpaceData, visitors: [UserData]) {
        self.space = space
        self.visitors = visitors
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "visitor_list".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: selectAllBtn)
        
        setupTableView()
        updateEmptyUI()
    }
    
    /// 选中所有
    @objc private func selectAllAction() {
        
        selectVisitors = visitors
        tableView.reloadData()
        clearSelectBtn.isEnabled = selectVisitors.count > 0
    }
    
    /// 清除选中访客
    @objc private func clearSelectBtnAction() {
        
        guard selectVisitors.count > 0 else {
            return
        }
        
        // 删除未在使用的访客
        
        // 是否有正在使用的访客
        SRAlertView(title: "notification".localizedString, message: "space_delete_used_visitors_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            // 删除使用中的访客
            guard let self = self else { return }
            let deleteIndexPaths = self.selectVisitors.compactMap({ visitor in
                if let row = self.visitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
                    return IndexPath(row: row, section: 0)
                }
                return nil
            })
            self.visitors.removeAll(where: { visitor in self.selectVisitors.contains(where: { $0.uuid == visitor.uuid }) })
            self.tableView.deleteRows(at: deleteIndexPaths, with: .fade)
            self.selectVisitors.removeAll()
            self.clearSelectBtn.isEnabled = self.selectVisitors.count > 0
            
            self.updateEmptyUI()
        })]).show()
        
    }
    
    /// 删除访客
    private func deleteVisitor(_ visitor: UserData) {
        
        // 检查是否正在使用space
        
        // 对应访客正在使用space
        SRAlertView(title: "notification".localizedString, message: "space_delete_visitor_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            // 删除访客
            guard let self = self else { return }
            if let row = self.visitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
                self.visitors.remove(at: row)
                self.tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
            }
            if let index = self.selectVisitors.firstIndex(where: { $0.uuid == visitor.uuid }) {
                self.selectVisitors.remove(at: index)
            }
            self.clearSelectBtn.isEnabled = self.selectVisitors.count > 0
            self.updateEmptyUI()
        })]).show()
        
        // 删除访客
        
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
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
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
        cell.deleteCallback = {[weak self] in
            // 删除访客
            self?.deleteVisitor(visitor)
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
