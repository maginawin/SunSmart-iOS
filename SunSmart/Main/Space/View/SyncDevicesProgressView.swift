//
//  SyncDevicesProgressView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/4.
//

import UIKit

class SyncDevicesProgressView: UIView {

    private var shadeView: UIView!
//    private var contentView: UIView!
    private var tableView: UITableView!
    /// 重新同步回调
    typealias ResyncActionCallback = ((SyncDeviceStepTaskModel)->Void)
    /// 关闭回调
    typealias ViewHideCallback = (()->Void)
    
    /// 任务步骤model
    var stepModel: SyncDeviceStepModel! {
        didSet {
            guard tableView != nil else {
                return
            }
            tableView.reloadData()
        }
    }
    
    var resyncCallback: ResyncActionCallback?
    
    var hideCallback: ViewHideCallback?
    
    init(frame: CGRect, stepModel: SyncDeviceStepModel) {
        super.init(frame: frame)
        self.stepModel = stepModel
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    static func show(stepModel: SyncDeviceStepModel, resync: ResyncActionCallback?, hide: ViewHideCallback?) {
        let view = SyncDevicesProgressView(frame: UIScreen.main.bounds, stepModel: stepModel)
        view.resyncCallback = resync
        view.hideCallback = hide
        UIApplication.shared.keyWindow().addSubview(view)
        view.showAnimation()
    }
    
    /// 获取当前展示的进度view
    static func current() -> SyncDevicesProgressView? {
        return UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: SyncDevicesProgressView.classForCoder()) }) as? SyncDevicesProgressView
    }
    
    public func hide() {
        
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.tableView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.hideCallback?()
        }

    }
    
    private func showAnimation() {
        shadeView.alpha = 0
        tableView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.tableView.alpha = 1
        }
    }
    
    @objc private func shadeViewAction() {
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        tableView = UITableView()
        tableView.backgroundColor = .white
        tableView.layer.cornerRadius = SCRYFrom(15)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(20), left: 0, bottom: SCRYFrom(20), right: 0)
        tableView.rowHeight = SCRYFrom(44)
        tableView.showsVerticalScrollIndicator = false
        tableView.register(SyncDevicesProgressViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.height.equalTo(tableView.rowHeight * CGFloat(min(stepModel.tasks.count, 5)) + tableView.contentInset.top + tableView.contentInset.bottom)
        }
        
    }
    
    
}

extension SyncDevicesProgressView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return stepModel.tasks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SyncDevicesProgressViewCell
        cell.taskModel = stepModel.tasks[indexPath.row]
        cell.resyncCallback = {[weak self] model in
            guard let self = self else { return }
            if self.stepModel.tasks.contains(where: { $0.state == .inSettings }) { // 是否有正在同步的数据
                model.state = .wait // 等待
                cell.taskModel = model
            }else { // 回调外部同步
                self.resyncCallback?(model)
            }
        }
        return cell
    }
    
}

class SyncDevicesProgressViewCell: UITableViewCell {
    
    private var nameLabel: UILabel!
    private var stateImageView: UIImageView!
    private var failureLabel: UILabel!
    private var resyncBtn: UIButton!
    
    var resyncCallback: ((SyncDeviceStepTaskModel)->Void)?
    
    
    var taskModel: SyncDeviceStepTaskModel! {
        didSet {
            
            nameLabel.text = taskModel.name
            stateImageView.isHidden = false
            failureLabel.isHidden = true
            resyncBtn.isHidden = true
            stateImageView.layer.removeAnimation(forKey: "loading")
            
            switch taskModel.state {
            case .none:
                stateImageView.isHidden = true
            case .wait:
                stateImageView.image = UIImage(named: "sync_waiting_small")
            case .successful:
                stateImageView.image = UIImage(named: "sync_success_small")
            case .failed:
                stateImageView.image = UIImage(named: "sync_failed_small")
                failureLabel.isHidden = false
                resyncBtn.isHidden = !taskModel.isFineshed
            case .inSettings:
                stateImageView.image = UIImage(named: "sync_loading_small")
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: 9999, animationKey: "loading")
            }
            
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func resyncBtnAction() {
        resyncCallback?(taskModel)
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "Schedule 1", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.width.lessThanOrEqualTo(SCRXFrom(150))
            make.centerY.equalToSuperview()
        }
        
        resyncBtn = UIButton(normalImageName: "scene_sync", target: self, action: #selector(resyncBtnAction))
        contentView.addSubview(resyncBtn)
        resyncBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-24))
            make.centerY.equalToSuperview()
        }
        
        failureLabel = UILabel(text: "failure".localizedString, textColor: Red_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(failureLabel)
        failureLabel.snp.makeConstraints { make in
            make.right.equalTo(resyncBtn.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
        
        stateImageView = UIImageView()
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(failureLabel.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
    }
    
}
