//
//  ScheduleAddView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit
import NordicSigMeshSDK

protocol ScheduleAddViewDelegate: AnyObject {
    
    /// 名称编辑回调
    /// - Parameters:
    ///   - view: self
    ///   - name: 名称
    /// - Returns: 是否需要提示（超长、重名）
    func view(_ view: ScheduleAddView, nameDidEditing name: String) -> String?
    
    /// 编辑数据后是否完成回调
    func view(_ view: ScheduleAddView, completionStateChanged completion: Bool)
}

class ScheduleAddView: UIView {
    
    var scrollView: UIScrollView!
    var contentView: UIView!
 
    /// name+enable
    private var infoView: UIView!
    private var nameField: UITextField!
    private var enabledSwitch: UISwitch!
    private var nameFailedLabel: UILabel!
    /// target
    var targetView: ScheduleAddTargetView!
    /// Action
    private var actionLabel: UILabel!
    private var actionOnBtn: UIButton!
    private var actionOffBtn: UIButton!
    private var actionRecallBtn: UIButton!
    private var lastSelectActionBtn: UIButton?
    /// Fade in
    private var fadeInLabel: UILabel!
    private var fadeTimeView: DeviceSliderFunctionView!

    weak var delegate: ScheduleAddViewDelegate?
    /// Time
    private var timeView: ScheduleTimeView!
    
    /// 名称
    var name: String {
        get {
            return nameField.text ?? ""
        }set {
            nameField.text = newValue
        }
    }
    /// 是否启用
    var enabled: Bool {
        get {
            return enabledSwitch.isOn
        }set {
            enabledSwitch.isOn = newValue
        }
    }
    
    /// 是否同步完成
    var isSyncCompletion: Bool = true {
        didSet {
            targetView.syncFaildTipBtn.isHidden = isSyncCompletion
        }
    }
    
    
    /// 选择的目标
    var selectTarget: ScheduleTarget? {
        didSet {
            if let targets = selectTarget {
                if case .scene = targets { // 场景
                    actionOnBtn.isHidden = true
                    actionOffBtn.isHidden = true
                    actionRecallBtn.isHidden = false
//                    actionRecallBtn.isSelected = true
                    actionBtnAction(sender: actionRecallBtn)
                    actionRecallBtn.snp.updateConstraints { make in
                        make.left.equalTo(SCRXFrom(20))
                    }
                }else { // 设备/组
                    actionOnBtn.isHidden = false
                    actionOffBtn.isHidden = false
                    actionRecallBtn.isHidden = true
                    actionRecallBtn.isSelected = false
                    actionRecallBtn.snp.updateConstraints { make in
                        make.left.equalTo(SCRXFrom(168))
                    }
                }
            }else { // 未选择
                actionOnBtn.isHidden = false
                actionOffBtn.isHidden = false
                actionRecallBtn.isHidden = true
                actionRecallBtn.isSelected = false
                
                actionRecallBtn.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(168))
                }
            }
            targetView.selectTarget = selectTarget
            
            lastUpdateCompletion = isCompletion
        }
    }
    
    /// 事件类型
    var actionType: SchedulerAction {
        get {
            var action: SchedulerAction = .noAction
            switch selectTarget {
            case .devices, .groups:
                if actionOnBtn.isSelected {
                    action = .turnOn
                }else if actionOffBtn.isSelected {
                    action = .turnOff
                }
            case .scene:
                return .sceneRecall
            case nil:
                break
            }
            return action
        }set {
            switch newValue {
            case .turnOn:
                actionBtnAction(sender: actionOnBtn)
            case .turnOff:
                actionBtnAction(sender: actionOffBtn)
            case .sceneRecall:
                actionBtnAction(sender: actionRecallBtn)
            default:
                actionOnBtn.isSelected = false
                actionOffBtn.isSelected = false
                actionRecallBtn.isSelected = false
            }
        }
    }
    
    /// 渐变时间
    var fadeTime: Int {
        get {
            return fadeTimeView.value
        }set {
            fadeTimeView.value = newValue
        }
    }
    /// 重复周
    var weekValue: Int {
        get {
            return timeView.weekValue
        }set {
            timeView.weekValue = newValue
        }
    }
    /// 时
    var hour: Int {
        get {
            return timeView.hour
        }set {
            timeView.hour = newValue
        }
    }
    /// 分
    var minute: Int {
        get {
            return timeView.minute
        }set {
            timeView.minute = newValue
        }
    }
    
    // 数据是否完整
    var isCompletion: Bool {
        // 名称合法
        if nameField.text == nil || nameField.text!.isAllInputTextEmpty() || nameFailedLabel.text?.count ?? 0 > 0 {
            return false
        }
        // target
        guard let selectTarget = self.selectTarget else { return false }
        switch selectTarget {
        case .scene:
            if !actionRecallBtn.isSelected {
                return false
            }
        default:
            if !actionOnBtn.isSelected && !actionOffBtn.isSelected {
                return false
            }
        }
        // week
        if timeView.weekValue == 0 { // 未选择重复周期
            return false
        }
        return true
    }
    /// 上次更新的完成状态
    private var lastUpdateCompletion: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
        
        timeView.weekValueChangedCallback = {[weak self] _ in
            self?.updateCompletionState()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更新数据完整状态
    private func updateCompletionState() {
        if lastUpdateCompletion != isCompletion {
            lastUpdateCompletion = isCompletion
            delegate?.view(self, completionStateChanged: isCompletion)
        }
    }
    
    // MARK: - Action
    /// 名称编辑
    @objc private func nameFieldEditChanged(sender: UITextField) {
        guard let name = sender.text else { return }
        let failedMessage = delegate?.view(self, nameDidEditing: name)
        nameFailedLabel.text = failedMessage
        updateCompletionState()
    }
    
    /// 触发事件点击
    @objc private func actionBtnAction(sender: UIButton) {
        
        lastSelectActionBtn?.isSelected = false
        lastSelectActionBtn?.backgroundColor = .white
        
        sender.isSelected = true
        sender.backgroundColor = Bar_Color
        
        lastSelectActionBtn = sender
        
        updateCompletionState()
    }
    
    @objc private func hideKeyboard() {
        endEditing(true)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tap.delegate = self
        contentView.addGestureRecognizer(tap)
        contentView.backgroundColor = Background_Color
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        infoView = UIView()
        infoView.backgroundColor = .white
        infoView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(infoView)
        infoView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(40))
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = FONTS(SCRYFrom(15))
        nameField.text = "Schedule 1"
//        nameField.clearButtonMode = .always
//        nameField.rightViewMode = .always
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        infoView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-70))
            make.centerY.height.equalToSuperview()
        }
        
        enabledSwitch = UISwitch()
        enabledSwitch.isOn = true
        enabledSwitch.onTintColor = Bar_Color
        enabledSwitch.tintColor = RGB(207, 207, 207)
        infoView.addSubview(enabledSwitch)
        enabledSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        nameFailedLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(nameFailedLabel)
        nameFailedLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.top.equalTo(infoView.snp.bottom).offset(SCRYFrom(2))
            make.right.equalTo(SCRXFrom(-24))
        }
        
        targetView = ScheduleAddTargetView()
        targetView.targets = [.devices([]), .groups([]), .scene(nil)]
        contentView.addSubview(targetView)
        targetView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-15))
            make.top.equalTo(infoView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(168))
        }
        
        actionLabel = UILabel(text: "action".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(actionLabel)
        actionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(28))
            make.top.equalTo(targetView.snp.bottom).offset(SCRYFrom(16))
        }
        
        actionOnBtn = UIButton(title: "action_on".localizedString, titleSize: 16, titleWeight: .light, titleColor: RGB(39, 37, 54), target: self, action: #selector(actionBtnAction))
        actionOnBtn.tag = 100
        actionOnBtn.setTitleColor(.white, for: .selected)
        actionOnBtn.layer.cornerRadius = SCRYFrom(6)
        actionOnBtn.backgroundColor = .white
        contentView.addSubview(actionOnBtn)
        actionOnBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(actionLabel.snp.bottom).offset(SCRYFrom(8))
            make.width.equalTo(SCRXFrom(64))
            make.height.equalTo(SCRYFrom(40))
        }
        
        actionOffBtn = UIButton(title: "action_off".localizedString, titleSize: 16, titleWeight: .light, titleColor: RGB(39, 37, 54), target: self, action: #selector(actionBtnAction))
        actionOffBtn.tag = 101
        actionOffBtn.setTitleColor(.white, for: .selected)
        actionOffBtn.layer.cornerRadius = SCRYFrom(6)
        actionOffBtn.backgroundColor = .white
        contentView.addSubview(actionOffBtn)
        actionOffBtn.snp.makeConstraints { make in
            make.left.equalTo(actionOnBtn.snp.right).offset(SCRXFrom(10))
            make.centerY.width.height.equalTo(actionOnBtn)
        }
        
        actionRecallBtn = UIButton(title: "recall".localizedString, titleSize: 16, titleWeight: .light, titleColor: RGB(39, 37, 54), target: self, action: #selector(actionBtnAction))
        actionRecallBtn.tag = 102
        actionRecallBtn.setTitleColor(.white, for: .selected)
        actionRecallBtn.layer.cornerRadius = SCRYFrom(6)
        actionRecallBtn.backgroundColor = .white
        contentView.addSubview(actionRecallBtn)
        actionRecallBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(168))
            make.centerY.width.height.equalTo(actionOnBtn)
        }
        
        fadeInLabel = UILabel(text: "fade_in".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(fadeInLabel)
        fadeInLabel.snp.makeConstraints { make in
            make.left.equalTo(actionLabel)
            make.top.equalTo(actionOnBtn.snp.bottom).offset(SCRYFrom(16))
        }
        
        fadeTimeView = DeviceSliderFunctionView(frame: .zero, title: "", value: 0, functionType: .level(min: 0, max: 60, step: 1, unit: "s", sliderColors: [RGB(255, 167, 44), RGB(229, 229, 229)]))
        fadeTimeView.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        fadeTimeView.minLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        fadeTimeView.minLabel.textColor = RGB(148, 163, 184)
        fadeTimeView.maxLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        fadeTimeView.minLabel.textColor = RGB(148, 163, 184)
        fadeTimeView.layer.cornerRadius = SCRYFrom(10)
        fadeTimeView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        fadeTimeView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        fadeTimeView.lineView.isHidden = true
        fadeTimeView.slider.snp.updateConstraints { make in
            make.left.equalTo(SCRXFrom(47))
            make.right.equalTo(SCRXFrom(-55))
        }
        fadeTimeView.backgroundColor = .white
        contentView.addSubview(fadeTimeView)
        fadeTimeView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-15))
            make.top.equalTo(fadeInLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(122))
        }
        
        timeView = ScheduleTimeView()
//        timeView.weekValue = 96
        timeView.hour = 8
        timeView.minute = 0
        contentView.addSubview(timeView)
        timeView.snp.makeConstraints { make in
            make.left.right.equalTo(targetView)
            make.top.equalTo(fadeTimeView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(284))
            make.bottom.equalTo(SCRYFrom(-10))
//            make.bottom.equalTo(SCRYFrom(-66) - kSafeAreaBottomHeight)
        }
        
    }
    
}

extension ScheduleAddView: UITextFieldDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        endEditing(true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.endEditing(true)
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        if let view = touch.view, NSStringFromClass(view.classForCoder) == "UITableViewCellContentView" {
            self.endEditing(true)
            return false
        }
        return true
    }
    
}


protocol ScheduleAddTargetViewDelegate: AnyObject {
    /// 点击target回调
    func view(_ view: ScheduleAddTargetView, didClickTargetAction target: ScheduleTarget)
    
    /// 点击同步失败提示回调
    func viewDidClickSyncFailedAction(_ view: ScheduleAddTargetView)
}

class ScheduleAddTargetView: UIView {
    
    
    private var targetLabel: UILabel!
    private var tableView: UITableView!
    var syncFaildTipBtn: UIButton!
    
    weak var delegate: ScheduleAddTargetViewDelegate?
    var targets: [ScheduleTarget] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    /// 选择的目标
    var selectTarget: ScheduleTarget? {
        didSet {
            tableView.reloadData()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 同步失败点击事件
    @objc private func syncFailedTipBtnAction() {
        delegate?.viewDidClickSyncFailedAction(self)
    }
    
    private func setupUI() {
        targetLabel = UILabel(text: "target".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(targetLabel)
        targetLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(8))
        }
        
        syncFaildTipBtn = UIButton(title: "devices_not_synced".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, normalImageName: "schedule_sync_failed", target: self, action: #selector(syncFailedTipBtnAction))
        syncFaildTipBtn.isHidden = true
        syncFaildTipBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(syncFaildTipBtn)
        syncFaildTipBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-1))
            make.centerY.equalTo(targetLabel)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.rowHeight = SCRYFrom(38)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(12), left: 0, bottom: SCRYFrom(12), right: 0)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.isScrollEnabled = false
        tableView.dataSource = self
        tableView.delegate = self
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(targetLabel.snp.bottom).offset(SCRYFrom(8))
        }
    }
    
}

extension ScheduleAddTargetView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return targets.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        
        cell.iconX = SCRXFrom(8)
        cell.titleX = SCRXFrom(42)
        let target = targets[indexPath.row]
        var names: [String] = []
        var emptyStr: String = ""
        
        var isSelected = false
        switch target {
        case .devices(let devices):
            cell.titleLabel.text = "devices".localizedString
            names = devices.map({ $0.name ?? "" })
            emptyStr = "select_devices".localizedString
            if case .devices = self.selectTarget {
                isSelected = true
            }
        case .groups(let groups):
            cell.titleLabel.text = "groups".localizedString
            names = groups.map({ $0.info.name ?? $0.name })
            emptyStr = "select_groups".localizedString
            if case .groups = self.selectTarget {
                isSelected = true
            }
        case .scene(let scene):
            cell.titleLabel.text = "scenes".localizedString
            if let name = scene?.info.name ?? scene?.name {
                names = [name]
            }
            emptyStr = "select_scenes".localizedString
            if case .scene = self.selectTarget {
                isSelected = true
            }
        }
        if names.isEmpty {
            cell.contentLabel.text = emptyStr
        }else {
            var content = ""
            names.forEach({ content.append(String(format: "%@%@", !content.isEmpty ? "," : "", $0)) })
            cell.contentLabel.text = content
        }
        cell.iconImageView.image = UIImage(named: isSelected ? "schedule_target_select" : "schedule_target_select_un")
        cell.iconImageView.isUserInteractionEnabled = false
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.titleLabel.textColor = RGB(39, 37, 54)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.selectionStyle = .none
        cell.lineView.isHidden = true
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.view(self, didClickTargetAction: targets[indexPath.row])
    }
    
}

class ScheduleTimeView: UIView {
    
    private var timeLabel: UILabel!
    
    private var weekBtns: [UIButton] = []
    private var timePickerView: MultiseriatePickerView!
    /// 重复周期更新回调
    var weekValueChangedCallback: ((Int)->Void)?
    
    /// 重复周期
    var weekValue: Int {
        get {
            var value = 0
            for (index, btn) in weekBtns.enumerated() {
                if btn.isSelected {
                    value += 1 << index
                }
            }
            return value
        }set {
            for (index, btn) in weekBtns.enumerated() {
                if newValue >> index & 1 == 1 {
                    btn.isSelected = true
                }else {
                    btn.isSelected = false
                }
                btn.backgroundColor = btn.isSelected ? Bar_Color : .white
            }
        }
    }
    
    /// 时
    var hour: Int {
        get {
            
            let selectRows = timePickerView.selectRows
            guard selectRows.count == 3 else {
                return 0
            }
            // 取值范围1~12
            // AM 1~11对应1点到11点，12点是中午12点
            // PM 1~11对应13点到23点，12就是午夜0点
            let isAM = selectRows[0] == 0
            // 转换24小时制
            let hour = selectRows[1] + 1 + (isAM ? 0 : 12) % 24
            return hour
        }set {
            var selectRows = timePickerView.selectRows
            guard selectRows.count == 3 else {
                return
            }
            // 0~23 % 12
            let isAM = newValue > 0 && newValue <= 12
            //0~23    0 12
            var hour = newValue % 12
            if hour == 0 {
                hour = 12
            }
            selectRows.replaceSubrange(0...1, with: [isAM ? 0 : 1, hour - 1])
            timePickerView.selectRows = selectRows
        }
    }
    
    /// 分钟
    var minute: Int {
        get {
            let selectRows = timePickerView.selectRows
            guard selectRows.count == 3 else {
                return 0
            }
            return selectRows[2]
        }set {
            var selectRows = timePickerView.selectRows
            guard selectRows.count == 3 else {
                return
            }
            selectRows.replaceSubrange(2...2, with: [newValue])
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func weekBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        sender.backgroundColor = sender.isSelected ? Bar_Color : .white
        
        weekValueChangedCallback?(weekValue)
    }
    
    private func setupUI() {
        
        timeLabel = UILabel(text: "select_days_and_time".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        timeLabel.sizeToFit()
        addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalToSuperview()
            make.height.equalTo(timeLabel.height)
        }
        
        var lastAddBtn: UIButton?
        for index in 0..<Schedule.weeklyStrs.count {
            let title = Schedule.weeklyStrs[index]
            let weekBtn = UIButton(title: title, titleSize: 16, titleWeight: .light, titleColor: RGB(39, 37, 54), target: self, action: #selector(weekBtnAction))
            weekBtn.layer.cornerRadius = SCRYFrom(6)
            weekBtn.setTitleColor(.white, for: .selected)
            weekBtn.backgroundColor = .white
            addSubview(weekBtn)
            weekBtn.snp.makeConstraints { make in
                if let lastAddBtn = lastAddBtn {
                    make.left.equalTo(lastAddBtn.snp.right).offset(SCRXFrom(10))
                    make.width.height.centerY.equalTo(lastAddBtn)
                    if index == Schedule.weeklyStrs.count - 1 {
                        make.right.equalToSuperview()
                    }
                }else {
                    make.left.equalToSuperview()
                    make.top.equalTo(timeLabel.snp.bottom).offset(SCRYFrom(8))
                    make.height.equalTo(SCRYFrom(40))
                }
            }
            lastAddBtn = weekBtn
            weekBtns.append(weekBtn)
        }
        
        let time = ["am".localizedString, "pm".localizedString]
        var hours: [String] = []
        var minutes: [String] = []
        for hour in 1...12 {
            hours.append("\(hour)")
        }
        for minute in 0...59 {
            minutes.append(String(format: "%02d", minute))
        }
        
        timePickerView = MultiseriatePickerView(frame: .zero, titles: [time, hours, minutes])
//        timePickerView.selectRows = [0, 8, 14]
        timePickerView.layer.cornerRadius = SCRYFrom(10)
        timePickerView.backgroundColor = .white
        addSubview(timePickerView)
        timePickerView.snp.makeConstraints { make in
            make.top.equalTo(timeLabel.snp.bottom).offset(SCRYFrom(60))
            make.left.right.bottom.equalToSuperview()
        }
    }
    
}

