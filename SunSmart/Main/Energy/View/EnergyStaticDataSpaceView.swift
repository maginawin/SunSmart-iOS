//
//  EnergyStaticDataSpaceView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/27.
//

import UIKit

protocol EnergyStaticDataSpaceViewDelegate: AnyObject {
    
    /// 采集新的能耗数据事件
    func spaceViewHarvestNewEnergyDataAction(_ view: EnergyStaticDataSpaceView)
    
    /// 查看历史采集的能耗数据事件
    func spaceViewViewHarvestHistoryAction(_ view: EnergyStaticDataSpaceView)
}

class EnergyStaticDataSpaceView: UIView {
    
    /// 能耗数据类型
    enum EnergyDataType {
        /// 总能耗
        case totalEnergy
        /// 最新的采集能耗数据
        case latestHarvestData
        /// 上一次采集能耗数据
        case previousHarvestData
        /// 采集间隔
        case harvestInterval
    }

    private var tableView: UITableView!
    private var harvestNewDataBtn: UIButton!
    private var viewHarvestHistoryBtn: UIButton!
    
    weak var delegate: EnergyStaticDataSpaceViewDelegate?
    
    private var sections: [[EnergyDataType]] = [[.totalEnergy], [.latestHarvestData, .previousHarvestData, .harvestInterval]]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 查看采集能耗历史数据
    @objc private func viewHarvestHistoryBtnAction() {
        
        delegate?.spaceViewViewHarvestHistoryAction(self)
    }
    
    /// 采集新能耗数据
    @objc private func harvestNewDataBtnAction() {
        
        delegate?.spaceViewHarvestNewEnergyDataAction(self)
    }
    
    private func setupUI() {
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(SpaceTotalHarvestDataCell.classForCoder(), forCellReuseIdentifier: "totalEnergyCell")
        tableView.register(SpaceHarvestDataHistoryCell.classForCoder(), forCellReuseIdentifier: "historyEnergyCell")
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(80) + kSafeAreaBottomHeight, right: 0)
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.bottom.equalToSuperview()
        }
        
        viewHarvestHistoryBtn = UIButton(titleSize: 15, titleColor: Bar_Color, fit: false, target: self, action: #selector(viewHarvestHistoryBtnAction))
        viewHarvestHistoryBtn.setAttributedTitle(NSAttributedString(string: "view_harvest_history".localizedString, attributes: [.underlineStyle: 1]), for: .normal)
        addSubview(viewHarvestHistoryBtn)
        viewHarvestHistoryBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.height.equalTo(SCRYFrom(20))
            make.bottom.equalTo(-kSafeAreaBottomHeight - SCRYFrom(8))
        }
        
        harvestNewDataBtn = UIButton(title: "harvest_new_energy_data".localizedString, titleSize: 16, titleWeight: .light, titleColor: .white, fit: false, target: self, action: #selector(harvestNewDataBtnAction))
        harvestNewDataBtn.layer.cornerRadius = SCRYFrom(10)
        harvestNewDataBtn.backgroundColor = Bar_Color
        addSubview(harvestNewDataBtn)
        harvestNewDataBtn.snp.makeConstraints { make in
            make.bottom.equalTo(viewHarvestHistoryBtn.snp.top).offset(SCRYFrom(-12))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(311))
            make.height.equalTo(SCRYFrom(44))
        }
    }
    
    
    class SpaceTotalHarvestDataCell: UITableViewCell {
        
        private var titleLabel: UILabel!
        private var totalEnergyUseLabel: UILabel!
        var totalEnergyDataLabel: UILabel!
        private var maxRatedEnergyUseLabel: UILabel!
        var maxRatedEnergyDataLabel: UILabel!
        /// 所有设备额定功率
        var ratedPowerBtn: UIButton!
        /// 节约比例
        var economyPercentageBtn: UIButton!
        /// 节约能源数据
        var economyValueBtn: UIButton!
        
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            
            selectionStyle = .none
            
            setupUI()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupUI() {
            
            titleLabel = UILabel(text: "all_lights:".localizedString, textColor: TextBlack_Color, fontSize: 14)
            contentView.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(14))
            }
            
            totalEnergyUseLabel = UILabel(text: "total_energy_use:".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
            contentView.addSubview(totalEnergyUseLabel)
            totalEnergyUseLabel.snp.makeConstraints { make in
                make.left.equalTo(titleLabel)
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(14))
            }
            
            totalEnergyDataLabel = UILabel(text: "--", textColor: TextBlack_Color, fontSize: 14)
            contentView.addSubview(totalEnergyDataLabel)
            totalEnergyDataLabel.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-16))
                make.bottom.equalTo(totalEnergyUseLabel).offset(SCRYFrom(-4))
            }
            
            maxRatedEnergyUseLabel = UILabel(text: "max_rated_energy_use:".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
            contentView.addSubview(maxRatedEnergyUseLabel)
            maxRatedEnergyUseLabel.snp.makeConstraints { make in
                make.left.equalTo(totalEnergyUseLabel)
                make.top.equalTo(totalEnergyUseLabel.snp.bottom).offset(SCRYFrom(12))
            }
            
            maxRatedEnergyDataLabel = UILabel(text: "--", textColor: TextBlack_Color, fontSize: 14)
            contentView.addSubview(maxRatedEnergyDataLabel)
            maxRatedEnergyDataLabel.snp.makeConstraints { make in
                make.right.equalTo(totalEnergyDataLabel)
                make.bottom.equalTo(maxRatedEnergyUseLabel).offset(SCRYFrom(-4))
            }
            
            ratedPowerBtn = UIButton(title: "1,000 kW", titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "energy_rated_power")
            ratedPowerBtn.isUserInteractionEnabled = false
            ratedPowerBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
            contentView.addSubview(ratedPowerBtn)
            ratedPowerBtn.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(19))
                make.bottom.equalTo(SCRYFrom(-16))
            }
            
            economyPercentageBtn = UIButton(title: "38.9%", titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "energy_reduce")
            economyPercentageBtn.isUserInteractionEnabled = false
            economyPercentageBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
            contentView.addSubview(economyPercentageBtn)
            economyPercentageBtn.snp.makeConstraints { make in
                make.centerX.equalToSuperview().offset(SCRXFrom(-4))
                make.centerY.equalTo(ratedPowerBtn)
            }
            
            economyValueBtn = UIButton(title: "17018.66 kWh", titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "energy_reduce")
            economyValueBtn.isUserInteractionEnabled = false
            economyValueBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
            contentView.addSubview(economyValueBtn)
            economyValueBtn.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-18))
                make.centerY.equalTo(economyPercentageBtn)
            }
        }
    }
    
    

    class SpaceHarvestDataHistoryCell: UITableViewCell {
        var titleLabel: UILabel!
        var timeLabel: UILabel!
        var harvestDataLabel: UILabel!
        var incompleteImageView: UIImageView!
        var lineView: UIView!
        
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            
            selectionStyle = .none
            
            setupUI()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupUI() {
            titleLabel = UILabel(text: "latest_harvest_data".localizedString, textColor: TextBlack_Color, fontSize: 14)
            contentView.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(14))
            }
            
            harvestDataLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
            contentView.addSubview(harvestDataLabel)
            harvestDataLabel.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-13))
                make.centerY.equalTo(titleLabel)
            }
            
            incompleteImageView = UIImageView(image: UIImage(named: "energy_incomplete"))
            incompleteImageView.isHidden = true
            contentView.addSubview(incompleteImageView)
            incompleteImageView.snp.makeConstraints { make in
                make.right.equalTo(harvestDataLabel.snp.left).offset(SCRXFrom(-4))
                make.centerY.equalTo(harvestDataLabel)
            }
            
            timeLabel = UILabel(text: "", textColor: Message_Color, fontSize: 14, fontWeight: .light)
            contentView.addSubview(timeLabel)
            timeLabel.snp.makeConstraints { make in
                make.left.equalTo(titleLabel)
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
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
    
}


extension EnergyStaticDataSpaceView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = sections[indexPath.section][indexPath.row]
        var cell: UITableViewCell!
        if option == .totalEnergy {
            let totalEnergyCell = tableView.dequeueReusableCell(withIdentifier: "totalEnergyCell", for: indexPath) as! SpaceTotalHarvestDataCell
            totalEnergyCell.totalEnergyDataLabel.text = "26782.02 kWh"
            totalEnergyCell.maxRatedEnergyDataLabel.text = "43800.68 kWh"
            totalEnergyCell.totalEnergyDataLabel.text = "26782.02 kWh"
            totalEnergyCell.ratedPowerBtn.setTitle("1000KW", for: .normal)
            totalEnergyCell.economyPercentageBtn.setTitle("38.9%", for: .normal)
            totalEnergyCell.economyValueBtn.setTitle("17018.66 kWh", for: .normal)
            cell = totalEnergyCell
        }else {
            let historyEnergyCell = tableView.dequeueReusableCell(withIdentifier: "historyEnergyCell", for: indexPath) as! SpaceHarvestDataHistoryCell
            historyEnergyCell.incompleteImageView.isHidden = true
            switch option {
            case .latestHarvestData:
                historyEnergyCell.titleLabel.text = "latest_harvest_data".localizedString
                historyEnergyCell.harvestDataLabel.text = "26782.02 kWh"
                historyEnergyCell.timeLabel.text = String.dateConvert(timestamp: "\(Int(Date().timeIntervalSince1970))", dateFormat: "M d, yyyy, hh:mm a")
                
            case .previousHarvestData:
                historyEnergyCell.titleLabel.text = "previous_harvest_data".localizedString
                historyEnergyCell.harvestDataLabel.text = "26000.00 kWh"
                historyEnergyCell.timeLabel.text = String.dateConvert(timestamp: "\(Int(Date().timeIntervalSince1970))", dateFormat: "M d, yyyy, hh:mm a")
            case .harvestInterval:
                
                historyEnergyCell.titleLabel.text = "interval".localizedString
                historyEnergyCell.harvestDataLabel.text = "782.02 kWh"
                let interval = 7500
                historyEnergyCell.timeLabel.text = String(format: "hour_minutes_interval".localizedString, interval / 3600, interval % 3600 / 60)
            default:
                break
            }
            historyEnergyCell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            cell = historyEnergyCell
        }
        cell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
      return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let option = sections[indexPath.section][indexPath.row]
        return option == .totalEnergy ? SCRYFrom(144) : SCRYFrom(72)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return SCRYFrom(8)
    }
}
