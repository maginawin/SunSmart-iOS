//
//  GroupSensorView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/4.
//

import UIKit
import NordicSigMeshSDK

protocol GroupSensorViewDelegate: AnyObject {
    
    func sensorViewDidShow(view: GroupSensorView)
    
    func sensorViewDidHide(view: GroupSensorView)
}

class GroupSensorView: UIView {
    
    /// 支持传感器类型
    enum SupportSensorType {
        case none
        /// 占用
        case presenceDetected
        /// 光照
        case ambientLight
        /// 占用+光照
        case all
    }
    
    /// 传感器类型
    enum SensorType {
        /// 占用
        case presenceDetected
        /// 光照
        case ambientLight
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    /// Top
    private var topView: UIView!
    private var sensorLabel: UILabel!
    private var arrowImageView: UIImageView!
    private var lightImageView: UIImageView!
    private var lightLuxLabel: UILabel!
    private var moveImageView: UIImageView!
    private var occupyStateImageView: UIImageView!
    var controlStateImageView: UIImageView!
    /// list
    var tableView: UITableView!
    
    private(set) var isShow: Bool = false
    /// 更新感应状态定时器
    private var updateOccupyTimer: Timer?
    /// 更新lux状态定时器
    private var updateLuxTimer: Timer?
    
    private var lastScrollOffsetY: CGFloat = 0
    
    weak var delegate: GroupSensorViewDelegate?
    
    /// 支持的传感器类型
    var supportSensorType: SupportSensorType = .all {
        didSet {
            controlStateImageView.isHidden = true
            switch supportSensorType {
            case .none:
                moveImageView.isHidden = true
                occupyStateImageView.isHidden = true
                lightImageView.isHidden = true
                lightLuxLabel.isHidden = true
            case .presenceDetected:
                moveImageView.isHidden = false
                occupyStateImageView.isHidden = false
                lightImageView.isHidden = true
                lightLuxLabel.isHidden = true
            case .ambientLight:
                moveImageView.isHidden = true
                occupyStateImageView.isHidden = true
                lightImageView.isHidden = false
                lightLuxLabel.isHidden = false
                lightLuxLabel.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-24))
                }
            case .all:
                moveImageView.isHidden = false
                occupyStateImageView.isHidden = false
                lightImageView.isHidden = false
                lightLuxLabel.isHidden = false
                lightLuxLabel.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-88))
                }
            }
        }
    }
    
    /// 传感器
    var sensors: [Node] = [] {
        didSet {
            
            sensorLabel.text = "\("sensor".localizedString)-\(sensors.count)"
            
            // 判断是否存在占用传感器
            if (supportSensorType == .presenceDetected || supportSensorType == .all), sensors.contains(where: { $0.presenceDetectedSensorModel != nil }) {
                moveImageView.isHidden = false
                occupyStateImageView.isHidden = false
          
                if sensors.contains(where: { $0.occupancyState && $0.state }) { // 存在感应状态
                    occupyStateImageView.image = UIImage(named: "sensor_occupy")
                    startUpdateOccupyTimer()
                }else {
                    occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
                }

            }else {
                moveImageView.isHidden = true
                occupyStateImageView.isHidden = true
                
//                lightLuxLabel.snp.updateConstraints { make in
//                    make.right.equalTo(SCRXFrom(-24))
//                }
            }
            
            // 判断是否存在光照传感器
            if supportSensorType == .ambientLight || supportSensorType == .all {
//                lightImageView.isHidden = false
//                lightLuxLabel.isHidden = false
                // 显示第一个光照传感器lux
                if let sensor = sensors.first(where: { $0.ambientLightSensorModel?.publish != nil && $0.sensorCalibrated && $0.steadyDaylightLux != nil && $0.state }) {
                    lightLuxLabel.text = "\(sensor.steadyDaylightLux!)lx"
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)
                    
                    controlStateImageView.isHidden = !sensor.lightControlOn
                    startUpdateLuxTimer()
                }else {
                    controlStateImageView.isHidden = true
                    lightLuxLabel.text = nil
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)
                    controlStateImageView.tintColor = .black
                }
            }
            tableView.reloadData()
//            reloadSensorData()
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
//        let pan = UIPanGestureRecognizer(target: self, action: #selector(scroll))
//        pan.delegate = self
//        self.addGestureRecognizer(pan)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        
        isShow = true
        delegate?.sensorViewDidShow(view: self)
        shadeView.isHidden = false
        topView.snp.updateConstraints { make in
            make.top.equalTo(SCRYFrom(8))
        }
        
        self.snp.updateConstraints { make in
            make.height.equalTo(self.superview!.height - self.superview!.safeAreaInsets.top)
        }
    
        self.arrowImageView.image = UIImage(named: "arrow_down")
        self.tableView.isHidden = false
        contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: 20, height: 20))
        
        self.layoutIfNeeded()
        self.contentView.y = self.height - self.topView.frame.maxY
        UIView.animate(withDuration: 0.3) {
//            self.layoutIfNeeded()
//            self.contentView.setNeedsLayout()
            self.contentView.y = self.height - self.contentView.height
//            self.arrowImageView.layer.addRotationAnimation(endLocation: 0.5, duration: 0.5)
        } completion: { _ in
            if self.tableView.firstShowFlashScrollIndicators {
                self.tableView.flashScrollIndicatorsIfNeeded()
            }
        }
    }
    
    func hide() {
     
        isShow = false
        delegate?.sensorViewDidHide(view: self)
        shadeView.isHidden = true
        topView.snp.updateConstraints { make in
            make.top.equalTo(0)
        }
        contentView.layer.mask = nil
        self.arrowImageView.image = UIImage(named: "arrow_up")
        
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - SCRYFrom(40) - kSafeAreaBottomHeight
            self.tableView.isHidden = true
        }completion: { _ in
            self.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(40) + kSafeAreaBottomHeight)
            }
            self.layoutIfNeeded()
            self.contentView.y = 0
        }
        
    }
    
    /// 刷新传感器数据（收到上报）
    /// - Parameters:
    ///   - sensor: 传感器节点
    ///   - sensorType: 传感器类型
    func reloadSensorData(sensor: Node, sensorType: SensorType) {

        if sensorType == .presenceDetected {
            if sensor.state && sensor.occupancyState {
                occupyStateImageView.image = UIImage(named: "sensor_occupy")
                startUpdateOccupyTimer()
            }else {
                occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
            }
        }else {
            if sensor.state, sensor.sensorCalibrated, let lux = sensor.steadyDaylightLux {
                lightLuxLabel.text = "\(lux)lx"
                lightLuxLabel.backgroundColor = RGB(179, 237, 103)
                startUpdateLuxTimer()
            }else {
                lightLuxLabel.text = nil
                lightLuxLabel.backgroundColor = RGB(245, 245, 245)
            }
        }
        
        if let index = sensors.firstIndex(where: { $0.primaryUnicastAddress == sensor.primaryUnicastAddress }) {
//            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? GroupSensorViewCell {
                cell.reloadSensorData(sensor: sensor, sensorType: sensorType)
            }
        }else {
            tableView.reloadData()
        }
        
    }
    
    /// 开始感应更新倒计时，5s内没有触发则显示无人状态
    private func startUpdateOccupyTimer() {
        
        stopUpdateOccupyTimer()
        
        updateOccupyTimer = LCWeakTimer.scheduledTimer(timeInterval: 5, aTarget: self, selector: #selector(updateOccupyState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateOccupyTimer!, forMode: .common)
    }
    
    private func stopUpdateOccupyTimer() {
        updateOccupyTimer?.invalidate()
        updateOccupyTimer = nil
    }
    
    @objc private func updateOccupyState() {
        stopUpdateOccupyTimer()
        occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
    }
    
    /// 开始lux更新倒计时，3s内没有新的数据则变为灰色背景
    private func startUpdateLuxTimer() {
        
        stopUpdateLuxTimer()
        
        updateLuxTimer = LCWeakTimer.scheduledTimer(timeInterval: 3, aTarget: self, selector: #selector(updateLuxState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateLuxTimer!, forMode: .common)
    }
    
    private func stopUpdateLuxTimer() {
        updateLuxTimer?.invalidate()
        updateLuxTimer = nil
    }
    
    @objc private func updateLuxState() {
        stopUpdateLuxTimer()
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
    }
    
    @objc private func shadeViewAction() {
        hide()
    }
    
    @objc private func topViewAction() {
        if isShow {
            hide()
        }else {
            show()
        }
    }
    
    @objc private func tableViewScroll(sender: UIPanGestureRecognizer) {
        let offset = sender.translation(in: tableView)
        if sender.state == .began {
            lastScrollOffsetY = offset.y
        }else if sender.state == .changed {
            
//            let offsetY = offset.y - lastScrollOffsetY
//            
//            if offsetY < 0 { // 向上
//                let showContentY = self.height - self.contentView.height
//                if contentView.y > showContentY {
//                    contentView.y += offsetY
//                }else {
//                    if tableView.contentOffset.y + tableView.height < tableView.contentSize.height {
//                        tableView.contentOffset = CGPoint(x: 0, y: tableView.contentOffset.y - offsetY)
//                    }
//                }
//                
//            }else {
//                
//                if tableView.contentOffset.y < 0 {
//                    contentView.y += offsetY
//                }else {
//                    tableView.contentOffset = CGPoint(x: 0, y: tableView.contentOffset.y - offsetY)
//                }
//            }
//            lastScrollOffsetY = offset.y
        }else if sender.state == .ended {
            
            // 判断滑动结束后距离起始点距离，>100则认为隐藏，否则还原；velocity滑动力度大的时候直接退出
            let showContentY = self.height - self.contentView.height
            
            if offset.y > 100 || sender.velocity(in: tableView).y > 1000 {
                hide()
            }else {
                UIView.animate(withDuration: 0.25) {
                    self.contentView.y = showContentY
                }
            }
            
        }

    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFrom(352) + kSafeAreaBottomHeight))
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(352) + kSafeAreaBottomHeight)
//            make.height.equalTo(SCRYFrom(40) + kSafeAreaBottomHeight)
        }
        
        topView = UIView()
//        topView.backgroundColor = .white
        topView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(topViewAction)))
        contentView.addSubview(topView)
        topView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(0)
            make.height.equalTo(SCRYFrom(40))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_up"))
        topView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.bottom.equalTo(SCRYFrom(-5))
        }
        
        sensorLabel = UILabel(text: "Sensor-6", textColor: TextBlack_Color, fontSize: 14)
        topView.addSubview(sensorLabel)
        sensorLabel.snp.makeConstraints { make in
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalTo(arrowImageView)
        }
        
        occupyStateImageView = UIImageView(image: UIImage(named: "sensor_unoccupy"))
        topView.addSubview(occupyStateImageView)
        occupyStateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-24))
            make.centerY.equalTo(sensorLabel)
        }
        
        moveImageView = UIImageView(image: UIImage(named: "sensor_move"))
        topView.addSubview(moveImageView)
        moveImageView.snp.makeConstraints { make in
            make.right.equalTo(occupyStateImageView.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(occupyStateImageView)
        }
        
        lightLuxLabel = UILabel(text: "", textColor: .black, fontSize: 12)
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
        lightLuxLabel.textAlignment = .center
        lightLuxLabel.layer.cornerRadius = SCRYFrom(10)
        lightLuxLabel.layer.masksToBounds = true
        topView.addSubview(lightLuxLabel)
        lightLuxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-88))
            make.centerY.equalTo(moveImageView)
            make.height.equalTo(SCRYFrom(20))
            make.width.equalTo(SCRXFrom(64))
        }
        
        lightImageView = UIImageView(image: UIImage(named: "sensor_light"))
        topView.addSubview(lightImageView)
        lightImageView.snp.makeConstraints { make in
            make.right.equalTo(lightLuxLabel.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(lightLuxLabel)
        }
        
        controlStateImageView = UIImageView(image: UIImage(named: "group_auto")?.withTintColor(.black))
        topView.addSubview(controlStateImageView)
        controlStateImageView.snp.makeConstraints { make in
            make.right.equalTo(lightImageView.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(lightImageView)
        }
        
        tableView = UITableView()
//        tableView.backgroundColor = .white
//        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.isHidden = true
        tableView.rowHeight = SCRYFrom(40)
        tableView.register(GroupSensorViewCell.classForCoder(), forCellReuseIdentifier: "cell")
//        tableView.panGestureRecognizer.delegate = self
//        let pan = UIPanGestureRecognizer(target: self, action: #selector(tableViewScroll))
//        self.addGestureRecognizer(pan)
//        tableView.addGestureRecognizer(pan)
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom).offset(SCRYFrom(3))
            make.left.right.bottom.equalToSuperview()
        }
        
        
        
    }
    
}

extension GroupSensorView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sensors.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GroupSensorViewCell
        let sensor = sensors[indexPath.row]
        cell.supportSensorType = supportSensorType
        cell.sensor = sensor
        return cell
    }
    
    
//    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        guard scrollView.isTracking else {
//            return
//        }
//        
//        let offsetY = scrollView.contentOffset.y
//        
//        if offsetY < 0 { // 向上
//            let showContentY = self.height - self.contentView.height
//            if contentView.y >= showContentY {
//                contentView.y += abs(offsetY)
//                scrollView.contentOffset = .zero
//            }else {
////                if tableView.contentOffset.y + tableView.height < tableView.contentSize.height {
////                    tableView.contentOffset = CGPoint(x: 0, y: tableView.contentOffset.y - offsetY)
//                }
//            }
////            
//        }else {
//            let showContentY = self.height - self.contentView.height
//            if contentView.y > showContentY {
//                contentView.y -= offsetY
//                scrollView.contentOffset = .zero
//            }
//        }
//        
////        if offsetY < 0 {
////            
////            contentView.y += abs(offsetY)
////            scrollView.contentOffset = .zero
////        }else if offsetY > 0 {
//            let showContentY = self.height - self.contentView.height
//            if contentView.y > showContentY {
//                contentView.y -= offsetY
//                scrollView.contentOffset = .zero
//            }
//        }
//        
//        lastScrollOffsetY = offsetY
//    }
//    
//    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
//        
//        // 判断滑动结束后距离起始点距离，>100则认为隐藏，否则还原；velocity滑动力度大的时候直接退出
//        let showContentY = self.height - self.contentView.height
//        if scrollView.contentOffset.y <= 0 && (contentView.y - showContentY >= 100 || velocity.y < -0.5) {
//            hide()
//        }else {
//            UIView.animate(withDuration: 0.25) {
//                self.contentView.y = showContentY
//            }
//        }
//    }
    
    
}


class GroupSensorViewCell: UITableViewCell {
    
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var lightLuxLabel: UILabel!
    var occupyStateImageView: UIImageView!
    /// 更新感应状态定时器
    private var updateOccupyTimer: Timer?
    private var updateLuxTimer: Timer?
    
    /// 支持的传感器类型
    var supportSensorType: GroupSensorView.SupportSensorType = .all {
        didSet {
            switch supportSensorType {
            case .none:
                occupyStateImageView.isHidden = true
                lightLuxLabel.isHidden = true
            case .presenceDetected:
                occupyStateImageView.isHidden = false
                lightLuxLabel.isHidden = true
            case .ambientLight:
                occupyStateImageView.isHidden = true
                lightLuxLabel.isHidden = false
                lightLuxLabel.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-24))
                }
            case .all:
                occupyStateImageView.isHidden = false
                lightLuxLabel.isHidden = false
                lightLuxLabel.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-88))
                }
            }
            
            nameLabel.snp.updateConstraints { make in
                let maxWidth = supportSensorType == .all ? SCRXFrom(160) : SCRXFrom(230)
                make.width.lessThanOrEqualTo(maxWidth)
            }
            
        }
    }
    
    var sensor: Node! {
        didSet {
            
            nameLabel.text = sensor.name
            iconImageView.image = UIImage(named: sensor.iconName)
            // 判断是否有占用传感器
            if sensor.presenceDetectedSensorModel != nil {
//                occupyStateImageView.isHidden = false
//                lightLuxLabel.snp.updateConstraints { make in
//                    make.right.equalTo(SCRXFrom(-88))
//                }
                if sensor.occupancyState { // 存在感应状态
                    occupyStateImageView.image = UIImage(named: "sensor_occupy")
                    startUpdateOccupyTimer()
                }else {
                    occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
                }
                
            }else {
                occupyStateImageView.isHidden = true
//                lightLuxLabel.snp.updateConstraints { make in
//                    make.right.equalTo(SCRXFrom(-24))
//                }
            }
            
            // 判断是否有光照传感器
            if sensor.sensorCalibrated, let model = sensor.ambientLightSensorModel, model.publish != nil, sensor.state, let lux = sensor.steadyDaylightLux {
                lightLuxLabel.text = "\(lux)lx"
                startUpdateLuxTimer()
            }else {
                lightLuxLabel.text = nil
                lightLuxLabel.backgroundColor = RGB(245, 245, 245)
            }
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupUI() {
        
        
        iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "device_light")
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "ID001", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalTo(iconImageView)
            make.width.lessThanOrEqualTo(SCRXFrom(230))
        }
        
        lightLuxLabel = UILabel(text: "", textColor: .black, fontSize: 12)
        lightLuxLabel.textAlignment = .center
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
        lightLuxLabel.layer.cornerRadius = SCRYFrom(10)
        lightLuxLabel.layer.masksToBounds = true
        contentView.addSubview(lightLuxLabel)
        lightLuxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-88))
            make.centerY.equalTo(nameLabel)
            make.height.equalTo(SCRYFrom(20))
            make.width.equalTo(SCRXFrom(64))
        }
        
        occupyStateImageView = UIImageView(image: UIImage(named: "sensor_unoccupy"))
        contentView.addSubview(occupyStateImageView)
        occupyStateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-24))
            make.centerY.equalTo(lightLuxLabel)
        }
        
    }
    
    
    /// 刷新传感器数据（收到上报）
    /// - Parameters:
    ///   - sensor: 传感器节点
    ///   - sensorType: 传感器类型
    func reloadSensorData(sensor: Node, sensorType: GroupSensorView.SensorType) {

        if sensorType == .presenceDetected {
            if sensor.occupancyState {
                occupyStateImageView.image = UIImage(named: "sensor_occupy")
                startUpdateOccupyTimer()
            }else {
                occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
            }
        }else {
            if sensor.sensorCalibrated, let lux = sensor.steadyDaylightLux {
                lightLuxLabel.text = "\(lux)lx"
                lightLuxLabel.backgroundColor = RGB(179, 237, 103)
                startUpdateLuxTimer()
            }else {
                lightLuxLabel.text = nil
                lightLuxLabel.backgroundColor = RGB(245, 245, 245)
            }
        }
    }
    
    /// 开始感应更新倒计时，5s内没有触发则显示无人状态
    private func startUpdateOccupyTimer() {
        
        stopUpdateOccupyTimer()
        
        updateOccupyTimer = LCWeakTimer.scheduledTimer(timeInterval: 5, aTarget: self, selector: #selector(updateOccupyState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateOccupyTimer!, forMode: .common)
    }
    
    private func stopUpdateOccupyTimer() {
        updateOccupyTimer?.invalidate()
        updateOccupyTimer = nil
    }
    
    @objc private func updateOccupyState() {
        stopUpdateOccupyTimer()
        occupyStateImageView.image = UIImage(named: "sensor_unoccupy")
    }
    
    /// 开始lux更新倒计时，3s内没有新的数据则变为灰色背景
    private func startUpdateLuxTimer() {
        
        stopUpdateLuxTimer()
        
        updateLuxTimer = LCWeakTimer.scheduledTimer(timeInterval: 3, aTarget: self, selector: #selector(updateLuxState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateLuxTimer!, forMode: .common)
    }
    
    private func stopUpdateLuxTimer() {
        updateLuxTimer?.invalidate()
        updateLuxTimer = nil
    }
    
    @objc private func updateLuxState() {
        stopUpdateLuxTimer()
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        stopUpdateOccupyTimer()
        stopUpdateLuxTimer()
    }
    
}
