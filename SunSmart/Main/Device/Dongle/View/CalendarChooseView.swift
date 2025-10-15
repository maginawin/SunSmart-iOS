//
//  CalendarChooseView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/23.
//

import UIKit

class CalendarChooseView: UIView {

//    enum DateType {
//        case specific(date: Date)
//        case section(startDate: Date, endDate: Date)
//    }
    /// 日历控件高度
    static let calenderViewHeight = SCRYFrom(274)
    
    typealias ChooseDateCallback = ((Date)->Bool)
    typealias CalenderHideCallback = (()->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var calendar: FSCalendar!
    private var dateLabel: UILabel!
    private var calendarLineView: UIView!
    private var beforeMonthBtn: UIButton!
    private var nextMonthBtn: UIButton!
    private var beforeYearBtn: UIButton!
    private var nextYearBtn: UIButton!
    private var maximumDate: Date = Date()
    private var minimumDate: Date = Date()
    private var selectCallback: ChooseDateCallback?
    private var hideCallback: CalenderHideCallback?
    private var showOffsetY: CGFloat = 0
    private var margin: CGFloat = SCRXFrom(16)
    
    init(minimumDate: Date, maximumDate: Date, selectDate: Date?, margin: CGFloat = SCRXFrom(16), showOffsetY: CGFloat, selectCallback: ChooseDateCallback?, hideCallback: CalenderHideCallback? = nil) {
        super.init(frame: UIScreen.main.bounds)
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.selectCallback = selectCallback
        self.showOffsetY = showOffsetY
        self.hideCallback = hideCallback
        self.margin = margin
        setupUI()
        
        if let date = selectDate {
            calendar.select(date, scrollToDate: true)
        }
        updateCalenderDateUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        layoutIfNeeded()
        contentView.y = showOffsetY
    }
    
    private func hide() {
        hideCallback?()
        self.removeFromSuperview()
    }
    
    @objc private func beforeYearAction() {
        
        let date = calendar.currentPage.getExpectDate(year: -1, month: 0, day: 0)
        calendar.setCurrentPage(date, animated: false)
        updateCalenderDateUI()
    }
    
    @objc private func beforeMonthAction() {
        
        let date = calendar.currentPage.getExpectDate(year: 0, month: -1, day: 0)
        calendar.setCurrentPage(date, animated: false)
        updateCalenderDateUI()
    }
    
    @objc private func nextYearAction() {
        
        let date = calendar.currentPage.getExpectDate(year: 1, month: 0, day: 0)
        calendar.setCurrentPage(date, animated: false)
        updateCalenderDateUI()
    }
    
    @objc private func nextMonthAction() {
        
        let date = calendar.currentPage.getExpectDate(year: 0, month: 1, day: 0)
        calendar.setCurrentPage(date, animated: false)
        updateCalenderDateUI()
    }
    
    @objc private func shadeViewAction() {
        hide()
    }
    
    private func updateCalenderDateUI() {
        let date = calendar.currentPage
        let timeInterval = Int64(date.timeIntervalSince1970)
        dateLabel.text = String.dateConvert(timestamp: "\(timeInterval)", dateFormat: calendar.appearance.headerDateFormat)
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(10)
        contentView.layer.shadowColor = RGB(0, 0, 0, 0.12).cgColor
        contentView.layer.shadowOpacity = 1
        contentView.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(Int(margin))
            make.right.equalTo(Int(-margin))
            make.height.equalTo(CalendarChooseView.calenderViewHeight)
        }
        
        dateLabel = UILabel(text: nil, textColor: RGB(0, 0, 0, 0.85), fontSize: 14)
        contentView.addSubview(dateLabel)
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(9))
            make.centerX.equalToSuperview()
        }
        
        beforeYearBtn = UIButton(normalImageName: "date_before_year", target: self, action: #selector(beforeYearAction))
        contentView.addSubview(beforeYearBtn)
        beforeYearBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalTo(dateLabel)
        }
        
        beforeMonthBtn = UIButton(normalImageName: "date_before_month", target: self, action: #selector(beforeMonthAction))
        contentView.addSubview(beforeMonthBtn)
        beforeMonthBtn.snp.makeConstraints { make in
            make.left.equalTo(beforeYearBtn.snp.right)
            make.centerY.equalTo(beforeYearBtn)
        }

        nextYearBtn = UIButton(normalImageName: "date_next_year", target: self, action: #selector(nextYearAction))
        contentView.addSubview(nextYearBtn)
        nextYearBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(dateLabel)
        }
        
        nextMonthBtn = UIButton(normalImageName: "date_next_month", target: self, action: #selector(nextMonthAction))
        contentView.addSubview(nextMonthBtn)
        nextMonthBtn.snp.makeConstraints { make in
            make.right.equalTo(nextYearBtn.snp.left)
            make.centerY.equalTo(nextYearBtn)
        }
        
        calendarLineView = UIView()
        calendarLineView.backgroundColor = RGB(0, 0, 0, 0.06)
        contentView.addSubview(calendarLineView)
        calendarLineView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(39))
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
        }
        
        calendar = FSCalendar()
        calendar.scrollEnabled = false
        calendar.weekdayHeight = SCRYFrom(22)
        calendar.rowHeight = SCRYFrom(36)
        calendar.headerHeight = 0
    //    _calendar.headerHeight = SCRYFrom(40);
//        calendar.appearance.headerTitleColor = RGB(0, 0, 0, 0.85)
//        calendar.appearance.borderRadius = SCRYFrom(5)
        if isChineseLanguage {
            calendar.appearance.headerDateFormat = "yyyy年MM月"
            calendar.firstWeekday = 2
        }else {
            calendar.appearance.headerDateFormat = "MMMM yyyy"
            calendar.firstWeekday = 1
        }
    
        calendar.scrollDirection = .horizontal
        calendar.appearance.weekdayTextColor = RGB(0, 0, 0, 0.85)
        calendar.appearance.weekdayFont = FONTS(SCRYFrom(12))
        calendar.appearance.titleFont = FONTS(SCRYFrom(12))
        calendar.appearance.titleDefaultColor = RGB(0, 0, 0, 0.85)
        calendar.appearance.selectionColor = Bar_Color
        calendar.appearance.titleTodayColor = RGB(0, 0, 0, 0.85)
//        calendar.appearance.headerTitleOffset = CGPoint(x: 0, y: SCRYFrom(-12))
    //    _calendar.appearance.todayColor = [UIColor clearColor];
    //    _calendar.appearance.todaySelectionColor = Bar_Color;
        calendar.locale = Locale.current
        calendar.today = nil
        calendar.dataSource = self
        calendar.delegate = self
        calendar.register(CalendarViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        contentView.addSubview(calendar)
        calendar.snp.makeConstraints { make in

            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(calendarLineView.snp.bottom).offset(SCRYFrom(16))
        }
        
        
    }
}

extension CalendarChooseView: FSCalendarDataSource, FSCalendarDelegate {
    
    func minimumDate(for calendar: FSCalendar) -> Date {
        return minimumDate
    }
    
    func maximumDate(for calendar: FSCalendar) -> Date {
        return maximumDate
    }
    
    func calendar(_ calendar: FSCalendar, shouldSelect date: Date, at monthPosition: FSCalendarMonthPosition) -> Bool {
        if selectCallback?(date) ?? false {
            hide()
            return true
        }
        return false
    }
    
    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        
    }
    
    func calendar(_ calendar: FSCalendar, shouldDeselect date: Date, at monthPosition: FSCalendarMonthPosition) -> Bool {
        return false
    }
    
    func calendar(_ calendar: FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        let cell = calendar.dequeueReusableCell(withIdentifier: "cell", for: date, at: position)
        return cell
    }
    
}


class CalendarViewCell: FSCalendarCell {
    
//    override init!(frame: CGRect) {
//        super.init(frame: frame)
//
//    }
//    
//    required init!(coder aDecoder: NSCoder!) {
//        fatalError("init(coder:) has not been implemented")
//    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        
        let maskPath = UIBezierPath(roundedRect: self.shapeLayer.bounds, cornerRadius: SCRYFrom(5))
        self.shapeLayer.path = maskPath.cgPath
        
    }
}
