//
//  DeviceParameterFilterView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/17.
//

import UIKit

class ParameterFilterData {
    
    enum ParameterType {
        var data: (imageName: String, title: String) {
            switch self {
            case .pwm:
                return ("pwm", "PWM")
            case .ratedPower:
                return ("rated_power", "rated_power".localizedString)
            case .absoluteSensitivity:
                return ("absolute_sensitivity", "absolute_sensitivity".localizedString)
            case .transitionTime:
                return ("transition_time", "transition_time".localizedString)
            }
        }
        
        case pwm
        case ratedPower
        case absoluteSensitivity
        case transitionTime
    }
    
    /// 参数类型
    let type: ParameterType
    /// 是否展开
    var isShow: Bool = false
    /// 内容list
    let contents: [String]
    /// 选择内容索引
    var selectIndex: Int?
    
    init(type: ParameterType, isShow: Bool = false, contents: [String], selectIndex: Int? = nil) {
        self.type = type
        self.isShow = isShow
        self.contents = contents
        self.selectIndex = selectIndex
    }
}

class DeviceParameterFilterView: UIView {

    /// 完成回调
    typealias DoneCallback = (([(type: ParameterFilterData.ParameterType, content: String, selectIndex: Int)])->Void)
    
    private let filterDatas: [ParameterFilterData]
    
    private let doneCallback: DoneCallback?
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var tableView: UITableView!
    private var lineView: UIView!
    private var resetBtn: UIButton!
    
    
    init(filterDatas: [ParameterFilterData], doneCallback: DoneCallback?) {
        self.filterDatas = filterDatas
        self.doneCallback = doneCallback
        super.init(frame: UIScreen.main.bounds)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
            self.layoutIfNeeded()
            contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(20), height: SCRYFrom(20)))
        }
        contentView.y = self.height
        
        self.shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
        } completion: { _ in
            
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.2) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func resetBtnAction() {
        filterDatas.forEach({
            $0.selectIndex = nil
        })
        tableView.reloadData()
    }
    
    @objc private func shadeViewAction() {
        let selectDatas = filterDatas.filter({ $0.selectIndex != nil })
        doneCallback?(selectDatas.map({ ($0.type, $0.contents[$0.selectIndex!], $0.selectIndex!) }))
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
        
        contentView = UIView()
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.snp.bottom)
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(416))
        }
        
        titleLabel = UILabel(text: "filter".localizedString, textColor: TextBlack_Color, fontSize: 16)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        resetBtn = UIButton(title: "Reset".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(resetBtnAction))
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(-kSafeAreaBottomHeight)
            make.height.equalTo(SCRYFrom(56))
            make.width.equalTo(SCRXFrom(120))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(resetBtn.snp.top)
            make.height.equalTo(1)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
//        tableView.rowHeight = SCRYFrom(36)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(ShareAuthorityFilterHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(48))
            make.bottom.equalTo(lineView.snp.top)
        }
        
        
    }
    
    
}

extension DeviceParameterFilterView: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return filterDatas.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let data = filterDatas[section]
        return data.isShow ? data.contents.count : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .none
        let data = filterDatas[indexPath.section]
        cell.titleLabel.text = data.contents[indexPath.row]
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.titleLabel.numberOfLines = 2
        cell.titleLabel.textColor = data.selectIndex == indexPath.row ? Bar_Color : TextBlack_Color
        cell.titleX = SCRXFrom(40)
        cell.titleMaxWidth = tableView.width * 0.8
        cell.lineView.isHidden = true
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! ShareAuthorityFilterHeaderView
        let data = filterDatas[section]
        headerView.iconImageView.image = UIImage(named: data.type.data.imageName)
        headerView.nameLabel.text = data.type.data.title
        headerView.arrowImageView.image = UIImage(named: data.isShow ? "arrow_up" : "arrow_right")
        headerView.arrowImageView.isHidden = false
        headerView.contentView.backgroundColor = RGB(216, 216, 216, 0.1)
        headerView.contentView.layer.cornerRadius = SCRYFrom(10)
        headerView.clickActionCallback = {
//            guard let self = self else { return }
            data.isShow = !data.isShow
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(36)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == tableView.numberOfSections - 1 ? 0 : SCRYFrom(8)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        let data = filterDatas[indexPath.section]
        if data.type == .ratedPower {
            return SCRYFrom(44)
        }
        return SCRYFrom(36)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        tableView.deselectRow(at: indexPath, animated: true)
        let data = filterDatas[indexPath.section]
        if data.selectIndex == indexPath.row {
            data.selectIndex = nil
        }else {
            data.selectIndex = indexPath.row
        }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }
}
