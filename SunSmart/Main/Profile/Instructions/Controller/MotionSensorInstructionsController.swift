//
//  MotionSensorInstructionsController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/27.
//

import UIKit

class MotionSensorInstructionsController: UIViewController {

    private lazy var tableView: UITableView = {
        let tableV = UITableView(frame: .zero, style: .grouped)
        tableV.separatorStyle = .none
        tableV.backgroundColor = Background_Color
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: SCRYFrom(10), right: 0)
        tableV.register(ProfileInstructionsHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableV.register(MotionSensorInstructionsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.estimatedRowHeight = SCRYFrom(44)
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    private var options: [Options] = [.maxLightOutput]
    
    /// 是否展开
    private var showOptionMap: [Options: Bool] = [:]
    
    let profile: Profile
    
    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "motion_sensor_instructions".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupDataSource()
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            let navHeight = navigationController?.navigationBar.height ?? kNavigationHeight
            make.top.equalTo(navHeight)
            make.left.right.bottom.equalToSuperview()
        }
    }
    
    private func setupDataSource() {
        
        
//            .maxLightOutput, .high_lowEndTrim, .occpancyLevel, .vacantLevel, .autoMiniValue, .t1, .t2, .t3, .t4, .t5
        profile.lightData.levels.forEach({ levelType in
            switch levelType {
            case .lightnessRange:
                options.append(.high_lowEndTrim)
            case .occupancyLevel:
                options.append(.occpancyLevel)
            case .vacantLevel:
                options.append(.vacantLevel)
            case .autoMinValue:
                options.append(.autoMinValue)
            case .taskLevel:
                options.append(.taskLevel)
            }
        })
        
        profile.lightData.times.forEach({ time in
            switch time {
            case .t1:
                options.append(.t1)
            case .t2:
                options.append(.t2)
            case .t3:
                options.append(.t3)
            case .t4:
                options.append(.t4)
            case .t5:
                options.append(.t5)
            }
        })
        
        
    }
    
    @objc private func back() {
        
        navigationController?.popViewController(animated: true)
    }

    

}

extension MotionSensorInstructionsController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return options.count
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let option = options[section]
        return (showOptionMap[option] ?? false) ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MotionSensorInstructionsViewCell
        let option = options[indexPath.section]
        cell.desc = option.description
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! ProfileInstructionsHeaderView
        let option = options[section]
        headerView.titleLabel.text = option.name
        headerView.isShow = showOptionMap[option] ?? false
        headerView.viewActionCallback = {[weak self] isShow in
            self?.showOptionMap[option] = isShow
            headerView.isShow = isShow
            tableView.reloadSections(IndexSet(integer: section), with: .fade)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
}


extension MotionSensorInstructionsController {
    
    enum Options {
        
        var name: String {
            switch self {
            case .maxLightOutput:
                return "profile_max_light_output".localizedString
            case .high_lowEndTrim:
                return "profile_high_low_end_trim".localizedString
            case .occpancyLevel:
                return "profile_occupancy_level".localizedString
            case .vacantLevel:
                return "profile_vacancy_level".localizedString
            case .autoMinValue:
                return "profile_auto_min_value".localizedString
            case .taskLevel:
                return "profile_task_level".localizedString
            case .t1:
                return "profile_t1".localizedString
            case .t2:
                return "profile_t2".localizedString
            case .t3:
                return "profile_t3".localizedString
            case .t4:
                return "profile_t4".localizedString
            case .t5:
                return "profile_t5".localizedString
            }
        }
        
        var description: String {
            switch self {
            case .maxLightOutput:
                return "profile_max_light_output_desc".localizedString
            case .high_lowEndTrim:
                return "profile_high_low_end_trim_desc".localizedString
            case .occpancyLevel:
                return "profile_occupancy_level_desc".localizedString
            case .vacantLevel:
                return "profile_vacancy_level_desc".localizedString
            case .autoMinValue:
                return "profile_auto_min_value_desc".localizedString
            case .taskLevel:
                return "profile_task_level_desc".localizedString
            case .t1:
                return "profile_t1_desc".localizedString
            case .t2:
                return "profile_t2_desc".localizedString
            case .t3:
                return "profile_t3_desc".localizedString
            case .t4:
                return "profile_t4_desc".localizedString
            case .t5:
                return "profile_t5_desc".localizedString
            }
        }
        
        /// 最大功率输出
        case maxLightOutput
        /// 亮度输出范围
        case high_lowEndTrim
        /// 占用阶段亮度
        case occpancyLevel
        /// 闲置阶段亮度
        case vacantLevel
        /// 恒照度补偿最低值
        case autoMinValue
        /// 维持亮度
        case taskLevel
        /// 启动到占用阶段过渡时间
        case t1
        /// 占用阶段持续时间
        case t2
        /// 占用阶段到闲置阶段过渡时间
        case t3
        /// 闲置阶段持续时间
        case t4
        /// 闲置阶段到休眠过渡时间
        case t5
    }
    
}
