//
//  MeshFirmwareUpgradeGuideView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/4.
//

import UIKit

class MeshFirmwareUpgradeGuideView: UIView {

    /// 流程
    enum Step {
        
        var data: (index: Int, title: String, imageName: String, showArrow: Bool, arrowY: CGFloat) {
            switch self {
            case .location:
                return (1, "mesh_distributor_guide_1".localizedString, "mesh_distributor_guide_1", true, arrowY: SCRYFrom(54))
            case .signal:
                return (2, "mesh_distributor_guide_2".localizedString, "mesh_distributor_guide_2", true, arrowY: SCRYFrom(57))
            case .identify:
                return (3, "mesh_distributor_guide_3".localizedString, "mesh_distributor_guide_3", true, arrowY: SCRYFrom(34))
            case .distributor:
                return (4, "mesh_distributor_guide_4".localizedString, "mesh_distributor_guide_4", false, arrowY: 0)
            case .selectDistributor:
                return (1, "mesh_upgrade_guide_1".localizedString, "mesh_upgrade_guide_1", true, arrowY: SCRYFrom(55))
            case .selectDevices:
                return (2, "mesh_upgrade_guide_2".localizedString, "mesh_upgrade_guide_2", true, arrowY: SCRYFrom(31))
            case .waiting:
                return (3, "mesh_upgrade_guide_3".localizedString, "mesh_upgrade_guide_3", false, arrowY: 0)
            }
        }
        
        var height: CGFloat {
            switch self {
            case .location:
                return SCRYFrom(167)
            case .signal:
                return SCRYFrom(180)
            case .identify:
                return SCRYFrom(128)
            case .distributor:
                return SCRYFrom(158)
            case .selectDistributor:
                return SCRYFrom(163)
            case .selectDevices:
                return SCRYFrom(135)
            case .waiting:
                return SCRYFrom(141)
            }
        }
         
        /// 升级 - 选择分发者
        case selectDistributor
        /// 升级 - 选择升级设备
        case selectDevices
        /// 升级 - 等待
        case waiting
        
        /// 分发 - 手机位置
        case location
        /// 分发 - 选择信号强的设备
        case signal
        /// 分发 - 识别
        case identify
        /// 分发 - 开始/下一步
        case distributor
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleView: UIView!
    private var closeBtn: UIButton!
    private var titleLabel: UILabel!
    private var tableView: UITableView!
    private var headerView: UIView!
    private var messageLabel: UILabel!
       
    private var steps: [Step]
    private var message: String
    private var contentHeight: CGFloat
    
    init(title: String, message: String, steps: [Step], contentHeight: CGFloat) {
        self.message = message
        self.steps = steps
        self.contentHeight = contentHeight
        super.init(frame: UIScreen.main.bounds)
        setupUI()
        
        self.titleLabel.text = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
        }
        showAnimation()
    }
    
    private func showAnimation() {
        self.layoutIfNeeded()
        shadeView.alpha = 0
        contentView.y = self.height
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.y = (self.height - self.contentView.height) * 0.5
        }
    }
    
    @objc private func hide() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        }completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = Background_Color
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.layer.masksToBounds = true
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-7))
//            make.top.equalTo(SCRYFrom(76))
//            make.bottom.equalTo(SCRYFrom(76))
            make.centerY.equalToSuperview()
            make.height.lessThanOrEqualTo(contentHeight)
        }
        
        
        titleView = UIView()
        contentView.addSubview(titleView)
        titleView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(44))
        }
        
        titleLabel = UILabel(text: "how_to_mesh_upgrade".localizedString, textColor: TextBlack_Color, fontSize: 16)
        titleView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalTo(titleView)
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(hide))
        titleView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalTo(titleLabel)
        }
        
        headerView = UIView()
        messageLabel = UILabel(text: message, textColor: Message_Color, fontSize: FontFit(13), fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        headerView.addSubview(messageLabel)

        let messageWidth = self.width - SCRXFrom(15) - SCRXFrom(88)
        let messageSize = (message as NSString).boundingRect(with: CGSize(width: messageWidth, height: CGFloat(MAXFLOAT)), options: .usesLineFragmentOrigin, attributes: [.font: UIFont.systemFont(ofSize: FontFit(13), weight: .light)], context: nil).size
        messageLabel.frame = CGRect(x: SCRXFrom(44), y: SCRYFrom(16), width: messageWidth, height: messageSize.height)
        headerView.frame = CGRect(x: 0, y: 0, width: self.width - SCRXFrom(15), height: messageSize.height + SCRYFrom(33))
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(MeshFirmwareUpgradeGuideStepViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(titleView.snp.bottom)
            var contentHeight = steps.reduce(0) { partialResult, step in
                partialResult + step.height
            }
            contentHeight += headerView.height
            make.height.equalTo(contentHeight).priority(.low)
        }
        
       
        tableView.tableHeaderView = headerView
        
    }
    
}

extension MeshFirmwareUpgradeGuideView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return steps.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareUpgradeGuideStepViewCell
        cell.step = steps[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return steps[indexPath.row].height
    }
    
}

class MeshFirmwareUpgradeGuideStepViewCell: UITableViewCell {
    
    var stepLabel: UILabel!
    var titleLabel: UILabel!
    var guideImageView: UIImageView!
    var arrowImageView: UIImageView!
    
    var step: MeshFirmwareUpgradeGuideView.Step! {
        didSet {
            let data = step.data
            stepLabel.text = "\(data.index)"
            titleLabel.text = data.title
            if data.showArrow {
                arrowImageView.isHidden = false
                arrowImageView.snp.updateConstraints { make in
                    make.top.equalTo(stepLabel.snp.bottom).offset(data.arrowY)
                }
            }else {
                arrowImageView.isHidden = true
            }
            guideImageView.image = UIImage(named: data.imageName)
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
    
    private func setupUI() {
        
        stepLabel = UILabel(text: "1", textColor: SubText_Color, fontSize: 14)
        stepLabel.layer.borderColor = SubText_Color.cgColor
        stepLabel.layer.borderWidth = 1
        stepLabel.layer.cornerRadius = SCRYFrom(10)
        stepLabel.textAlignment = .center
        contentView.addSubview(stepLabel)
        stepLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(20))
        }
        
        titleLabel = UILabel(text: "", textColor: SubText_Color, fontSize: FontFit(14), fontWeight: .light, fit: false)
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(stepLabel.snp.right).offset(SCRXFrom(9))
            make.top.equalTo(stepLabel).offset(SCRYFrom(2))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        guideImageView = UIImageView()
        contentView.addSubview(guideImageView)
        guideImageView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(30))
            make.centerX.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "step_arrow_down"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.top.equalTo(stepLabel.snp.bottom).offset(0)
            make.centerX.equalTo(stepLabel)
        }
        
    }
    
    
    
}
