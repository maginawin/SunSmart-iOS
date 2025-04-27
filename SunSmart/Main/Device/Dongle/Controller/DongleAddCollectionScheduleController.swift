//
//  DongleAddCollectionScheduleController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DongleAddCollectionScheduleController: UIViewController {
    
    /// Date
    private var selectDateLabel: UILabel!
    private var selectDateView: UIView!
    private var dateImageView: UIImageView!
    private var dateLabel: UILabel!
    
    /// Time
    private var selectTimeLabel: UILabel!
    private var timePickerView: MultiseriatePickerView!
    
    /// Action
    private var selectActionLabel: UILabel!
    private var enableActionBtn: UIButton!
    private var disableActionBtn: UIButton!
    
    /// Bottom
    private var bottomView: DeviceBottomBtnView!
    /// 选择日期的时间戳（年月日）
    private var selectDateTimestamp: Int64 = 0
    /// 选择时分的时间戳（时分）
    private var selectTimeTimestamp: Int64 = 0
    
    private var setSchedule: DeviceDongleData.CollectionSchedule!
    let schedule: DeviceDongleData.CollectionSchedule?
    let dongleData: DeviceDongleData
    
    /// 日程添加/编辑回调
    var scheudleDoneCallback: ((DeviceDongleData.CollectionSchedule)->Void)?
    /// 日程删除回调
    var scheudleDeleteCallback: ((DeviceDongleData.CollectionSchedule)->Void)?
    
    init(dongleData: DeviceDongleData, schedule: DeviceDongleData.CollectionSchedule?) {
        self.schedule = schedule
        self.dongleData = dongleData
        super.init(nibName: nil, bundle: nil)
        
        self.setSchedule = schedule?.copy() ?? .default(id: dongleData.nextScheduleId() ?? 0)
        
        let result = Date(timeIntervalSince1970: TimeInterval(self.setSchedule.timestamp)).splitTimestamp()
        self.selectDateTimestamp = Int64(result.dateTimestamp)
        self.selectTimeTimestamp = Int64(result.timeTimestamp)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if self.schedule != nil {
            title = "edit_collection_schedule".localizedString
        }else {
            title = "add_collection_schedule".localizedString
        }
        view.backgroundColor = Background_Color
        
        setupUI()
        
        updateUI()
    }
    
    private func updateUI() {
        
        var dateFormat = "M/d/yyyy"
        if isChineseLanguage {
            dateFormat = "yyyy/M/d"
        }
        
        dateLabel.text = String.dateConvert(timestamp: "\(selectDateTimestamp)", dateFormat: dateFormat)
        
        let hour = String.getTimeStringHour(timestamp: "\(selectDateTimestamp + selectTimeTimestamp)")
        let minute = String.getTimeStringMinute(timestamp: "\(selectDateTimestamp + selectTimeTimestamp)")
        timePickerView.hour = hour
        timePickerView.minute = minute
        
        if setSchedule.state == .enable {
            enableActionBtn.isSelected = true
            disableActionBtn.isSelected = false
        }else {
            enableActionBtn.isSelected = false
            disableActionBtn.isSelected = true
        }
        
        bottomView.showCreateUI()
        
    }
    
    @objc private func enableActionBtnAction(sender: UIButton) {
        sender.isSelected = true
        disableActionBtn.isSelected = false
        setSchedule.state = .enable
    }
    
    @objc private func disableActionBtnAction(sender: UIButton) {
        sender.isSelected = true
        enableActionBtn.isSelected = false
        setSchedule.state = .disable
    }
    
    /// 完成
    @objc private func doneAction() {
        setSchedule.timestamp = selectDateTimestamp + selectTimeTimestamp
        scheudleDoneCallback?(setSchedule)
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func selectDateAction() {
        
        let offsetY = view.convert(CGPoint(x: 0, y: selectDateView.frame.maxY + SCRYFrom(4)), to: UIApplication.shared.keyWindow()).y
        let currentDate = Date()
        CalendarChooseView(minimumDate: currentDate, maximumDate: currentDate.getExpectDate(year: 10, month: 0, day: 0), selectDate: Date(timeIntervalSince1970: TimeInterval(selectDateTimestamp)), showOffsetY: offsetY) {[weak self] selectDate in
            guard let self = self else { return true }
//            self.setSchedule.timestamp = Int64(selectDate.timeIntervalSince1970)
            self.selectDateTimestamp = Int64(selectDate.timeIntervalSince1970)
            self.updateUI()
            print(selectDate)
            return true
        }.show()
        
    }
    
    private func setupUI() {
        
        selectDateLabel = UILabel(text: "1." + "select_date".localizedString, textColor: TextBlack_Color, fontSize: 14)
        view.addSubview(selectDateLabel)
        selectDateLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(28))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(8))
//            make.top.equalTo((view.safeAreaLayoutGuide) + SCRYFrom(8))
        }
        
        selectDateView = UIView()
        selectDateView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectDateAction)))
        selectDateView.backgroundColor = .white
        selectDateView.layer.cornerRadius = SCRYFrom(10)
        view.addSubview(selectDateView)
        selectDateView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(selectDateLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(44))
        }
        
        dateImageView = UIImageView(image: UIImage(named: "dongle_schedule"))
        selectDateView.addSubview(dateImageView)
        dateImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        dateLabel = UILabel(text: "6/10/2025", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        selectDateView.addSubview(dateLabel)
        dateLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        selectTimeLabel = UILabel(text: "2." + "select_time".localizedString, textColor: TextBlack_Color, fontSize: 14)
        view.addSubview(selectTimeLabel)
        selectTimeLabel.snp.makeConstraints { make in
            make.left.equalTo(selectDateLabel)
            make.top.equalTo(selectDateView.snp.bottom).offset(SCRYFrom(16))
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
        timePickerView.layer.cornerRadius = SCRYFrom(10)
        timePickerView.backgroundColor = .white
        timePickerView.pickerBack = {[weak self] _ in
            guard let self = self else { return }
            self.selectTimeTimestamp = Int64((self.timePickerView.hour * 3600 + self.timePickerView.minute * 60))
        }
        view.addSubview(timePickerView)
        timePickerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(selectTimeLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(202))
        }
        
        selectActionLabel = UILabel(text: "3." + "select_action".localizedString, textColor: TextBlack_Color, fontSize: 14)
        view.addSubview(selectActionLabel)
        selectActionLabel.snp.makeConstraints { make in
            make.left.equalTo(selectTimeLabel)
            make.top.equalTo(timePickerView.snp.bottom).offset(SCRYFrom(16))
        }
        
        let actionBtnSize = CGSize(width: Int(SCRXFrom(80)), height: Int(SCRYFrom(32)))
        enableActionBtn = UIButton(title: "enable".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(46, 49, 93), target: self, action: #selector(enableActionBtnAction))
        enableActionBtn.setTitleColor(.white, for: .selected)
        enableActionBtn.layer.cornerRadius = SCRYFrom(6)
        enableActionBtn.layer.masksToBounds = true
        enableActionBtn.setBackgroundImage(UIImage.image(size: actionBtnSize, color: .white), for: .normal)
        enableActionBtn.setBackgroundImage(UIImage.image(size: actionBtnSize, color: Bar_Color), for: .selected)
        view.addSubview(enableActionBtn)
        enableActionBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(selectActionLabel.snp.bottom).offset(SCRYFrom(8))
            make.size.equalTo(actionBtnSize)
        }
        
        disableActionBtn = UIButton(title: "disable".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(46, 49, 93), target: self, action: #selector(disableActionBtnAction))
        disableActionBtn.setTitleColor(.white, for: .selected)
        disableActionBtn.layer.cornerRadius = SCRYFrom(6)
        disableActionBtn.layer.masksToBounds = true
        disableActionBtn.setBackgroundImage(UIImage.image(size: actionBtnSize, color: .white), for: .normal)
        disableActionBtn.setBackgroundImage(UIImage.image(size: actionBtnSize, color: Bar_Color), for: .selected)
        view.addSubview(disableActionBtn)
        disableActionBtn.snp.makeConstraints { make in
            make.left.equalTo(enableActionBtn.snp.right).offset(SCRXFrom(10))
            make.top.size.equalTo(enableActionBtn)
        }
        
        bottomView = DeviceBottomBtnView()
        bottomView.createBtn.setTitle("done".localizedString, for: .normal)
        bottomView.createBtn.setTitleColor(TextBlack_Color, for: .normal)
        bottomView.createBtn.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
    }
    

}

extension MultiseriatePickerView {
    
    /// 时
    var hour: Int {
        get {
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
            var setSelectRows = selectRows
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
            setSelectRows.replaceSubrange(0...1, with: [isAM ? 0 : 1, hour - 1])
            self.selectRows = setSelectRows
        }
    }
    
    /// 分钟
    var minute: Int {
        get {
            guard selectRows.count == 3 else {
                return 0
            }
            return selectRows[2]
        }set {
            var setSelectRows = selectRows
            guard selectRows.count == 3 else {
                return
            }
            setSelectRows.replaceSubrange(2...2, with: [newValue])
            self.selectRows = setSelectRows
        }
    }
    
    
}
