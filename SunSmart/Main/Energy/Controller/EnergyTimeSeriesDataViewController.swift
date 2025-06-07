//
//  EnergyTimeSeriesDataViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit
import NordicSigMeshSDK

class EnergyTimeSeriesDataViewController: UIViewController {

    /// 导出目标数据
    enum ExportTarget: Int{
        
        var name: String {
            switch self {
            case .space:
                return "space".localizedString
            case .devices:
                return "device".localizedString
            }
        }
        
        /// space全部数据
        case space = 0
        /// 对应设备数据
        case devices
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var importView: EnergyTimeSeriesDataImportView!
    private var exportView: EnergyTimeSeriesDataExportView!
    private var exportTarget: ExportTarget = .space
    private var exportStartDate: Date?
    private var exportEndDate: Date?
    
    private var devices: [Node] = []
    /// 选择导出的设备
    private var selectExportDevices: [Node] = []
    private weak var harvestStateView: EnergyHarvestStateView?
    
    let space: SpaceData
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        devices = MeshNetworkManager.instance.realNodes
        
        setupUI()
        
        updateUI()
    }
    
    private func updateUI() {
        // 是否有导出能耗数据文件
        if true {
            importView.fileDataView.isHidden = false
            importView.noDataLabel.isHidden = true
            // 文件名称
            importView.fileNameLabel.text = "Time Series Data 2-20-2025 10:30 PM"
            // 文件大小
            importView.fileSizeLabel.text = "10M"
        }else {
            importView.fileDataView.isHidden = true
            importView.noDataLabel.isHidden = false
        }
        
        if exportTarget == .space {
            exportView.exportRangeBtn.setTitle("space".localizedString, for: .normal)
            exportView.exportRangeBtn.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-16))
                make.width.equalTo(SCRXFrom(156))
            }
            exportView.exportRangeEditBtn.isHidden = true
        }else {
            exportView.exportRangeBtn.setTitle("device".localizedString, for: .normal)
            exportView.exportRangeBtn.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-57))
                make.width.equalTo(SCRXFrom(115))
            }
            exportView.exportRangeEditBtn.isHidden = false
        }
        
        var startDateStr: String?
        if let stateDate = self.exportStartDate {
            startDateStr = String.dateConvert(timestamp: "\(Int64(stateDate.timeIntervalSince1970))", dateFormat: "yyyy-MM-dd")
        }
        exportView.startDateBtn.setTitle(startDateStr, for: .normal)
        
        var endDateStr: String?
        if let endDate = self.exportEndDate {
            endDateStr = String.dateConvert(timestamp: "\(Int64(endDate.timeIntervalSince1970))", dateFormat: "yyyy-MM-dd")
        }
        exportView.endDateBtn.setTitle(endDateStr, for: .normal)
        
        if exportEndDate == nil || exportStartDate == nil || devices.isEmpty { // || 文件不存在
            exportView.exportBtn.isUserInteractionEnabled = false
            exportView.exportBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
        }else {
            exportView.exportBtn.isUserInteractionEnabled = true
            exportView.exportBtn.backgroundColor = Bar_Color
        }
        
    }
    
    /// 能耗数据导入到手机
    @objc private func importAction() {
        
        let selectView = ImportEnergyDeviceSelectView(frame: UIScreen.main.bounds)
        selectView.delegate = self
        selectView.show()
        
        
//        let dongleDevices = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .dongle })
////        dongleDevices.first(where: {  })
//        if dongleDevices.isEmpty {
//            // 没有能耗采集设备
//            SRAlertView(title: "import".localizedString, message: "import_no_energy_storage_device".localizedString, actions: [SRAlertAction(title: "GOT IT".localizedString)]).show()
//            return
//        }
        // 获取打开能耗采集的设备
        
        
        
    }
    
    /// 开始导出
    @objc private func exportAction() {
        guard let startDate = self.exportStartDate, let endDate = self.exportEndDate else { return }
        let timeInterval = startDate.distance(to: endDate)
        if timeInterval < 0 {
            XWHUDManager.showTipHUD("export_date_start_greater_than_end".localizedString, isLineFeed: true)
            return
        }
        // 导出CSV文件
        
        
    }
    
    /// 能耗导出范围
    @objc private func exportRangeAction(sender: UIButton) {
        let targets: [ExportTarget] = [.space, .devices]
        let selectIndex = targets.firstIndex(where: { $0.rawValue == exportTarget.rawValue })
        let menuWidth = SCRXFrom(164)
        let touchPoint = CGPoint(x: sender.x, y: sender.frame.maxY + SCRYFrom(2))
        let menuPoint = exportView.convert(touchPoint, to: UIApplication.shared.keyWindow())    
        
        TitleSelectView.show(titles: targets.map({ $0.name }), anchorPoint: menuPoint, selectIndex: selectIndex ?? 0, menuWidth: menuWidth) {[weak self] index in
            guard let self = self else { return }
            let selectTarget = targets[index]
            if selectTarget == .devices {
                self.selectExportDevices.removeAll()
                self.selectExportDevicesAction()
            }
            self.exportTarget = targets[index]
            self.updateUI()
//            self.devicesTableView.reloadData()
        }
    }

    /// 选择导出设备
    @objc private func selectExportDevicesAction() {
        
        let vc = EnergySelectExportDevicesController(devices: devices, selectDevices: selectExportDevices)
        vc.devicesSelectDoneCallback = {[weak self] selectDevices in
            guard let self = self else { return }
            self.selectExportDevices = selectDevices
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 构建数据类型
    @objc private func buildingTypeAction() {
        // TODO
    }
    
    /// 导出数据开始日期
    @objc private func exportStartDateAction(sender: UIButton) {
        
        let viewPoint = exportView.convert(CGPoint(x: 0, y: sender.frame.maxY + SCRYFrom(4)), to: view)
        var showOffsetY = view.convert(viewPoint, to: UIApplication.shared.keyWindow()).y
        // 高度超出屏幕时显示到按键上面
        if showOffsetY + CalendarChooseView.calenderViewHeight > SCREEN_HEIGHT {
            showOffsetY -= (sender.height + SCRYFrom(8) + CalendarChooseView.calenderViewHeight)
        }
        
        sender.layer.borderColor = Bar_Color.cgColor
        
        CalendarChooseView(minimumDate: Date().getExpectDate(year: -3, month: 0, day: 0), maximumDate: self.exportEndDate ?? Date(), selectDate: exportStartDate, showOffsetY: showOffsetY) {[weak self] date in
            guard let self = self else { return false }
            
            // 开始时间大于结束时间
            if let endDate = self.exportEndDate {
                let timeInterval = date.distance(to: endDate)
                // 开始时间不能大于结束时间
                if timeInterval < 0 {
                    XWHUDManager.showTipHUD("export_date_start_greater_than_end".localizedString, isLineFeed: true)
                    return false
                }
                // 导出时间范围间隔不能大于365天
                if timeInterval > 365 * 24 * 3600 {
                    XWHUDManager.showTipHUD("export_date_range_overrun".localizedString, isLineFeed: true)
                    return false
                }
                // 判断选择的时间是否有数据
//                if  {
//                    XWHUDManager.showTipHUD("export_date_greater_than_import_date".localizedString, isLineFeed: true)
//                    return false
//                }
            }
            self.exportStartDate = date
            self.updateUI()
            return true
        } hideCallback: {
            sender.layer.borderColor = RGB(220, 220, 220).cgColor
        }.show()
        
    }
    
    ///  导出数据结束日期
    @objc private func exportEndDateAction(sender: UIButton) {
        
        let viewPoint = exportView.convert(CGPoint(x: 0, y: sender.frame.maxY + SCRYFrom(4)), to: view)
        var showOffsetY = view.convert(viewPoint, to: UIApplication.shared.keyWindow()).y
        // 高度超出屏幕时显示到按键上面
        if showOffsetY + CalendarChooseView.calenderViewHeight > SCREEN_HEIGHT {
            showOffsetY -= (sender.height + SCRYFrom(8) + CalendarChooseView.calenderViewHeight)
        }
        
        CalendarChooseView(minimumDate: self.exportStartDate ?? Date().getExpectDate(year: -3, month: 0, day: 0), maximumDate: Date(), selectDate: exportEndDate, showOffsetY: showOffsetY) {[weak self] date in
            guard let self = self else { return false }
            
            if let startDate = self.exportStartDate {
                let timeInterval = startDate.distance(to: date)
                // 结束时间小于开始时间
                if timeInterval < 0 {
                    XWHUDManager.showTipHUD("export_date_end_less_than_start".localizedString, isLineFeed: true)
                    return false
                }
                // 判断选择的时间是否有数据
//                if  {
//                    XWHUDManager.showTipHUD("export_date_greater_than_import_date".localizedString, isLineFeed: true)
//                    return false
//                }
                
            }
            self.exportEndDate = date
            self.updateUI()
            return true
        } hideCallback: {
            sender.layer.borderColor = RGB(220, 220, 220).cgColor
        }.show()
        
    }
    
    
    private func setupUI() {
        
        importView = EnergyTimeSeriesDataImportView()
        importView.importBtn.addTarget(self, action: #selector(importAction), for: .touchUpInside)
        view.addSubview(importView)
        importView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(20))
            make.height.equalTo(SCRYFrom(144))
        }
        
        exportView = EnergyTimeSeriesDataExportView()
        exportView.exportRangeBtn.addTarget(self, action: #selector(exportRangeAction), for: .touchUpInside)
        exportView.exportRangeEditBtn.addTarget(self, action: #selector(selectExportDevicesAction), for: .touchUpInside)
        exportView.buildingTypeBtn.addTarget(self, action: #selector(buildingTypeAction), for: .touchUpInside)
        exportView.startDateBtn.addTarget(self, action: #selector(exportStartDateAction), for: .touchUpInside)
        exportView.endDateBtn.addTarget(self, action: #selector(exportEndDateAction), for: .touchUpInside)
        exportView.exportBtn.addTarget(self, action: #selector(exportAction), for: .touchUpInside)
        view.addSubview(exportView)
        exportView.snp.makeConstraints { make in
            make.left.right.equalTo(importView)
            make.top.equalTo(importView.snp.bottom).offset(SCRYFrom(11.5))
            make.height.equalTo(SCRYFrom(258))
        }
    }
    

}


extension EnergyTimeSeriesDataViewController: ImportEnergyDeviceSelectViewDelegate {
    
    /// 能耗采集设备识别
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDeviceIdentify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 刷新能耗采集设备信号
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDevicesRefresh devices: [Node]) {
        
        devices.forEach({ $0.rssi = nil })
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 9.6) { _ in
            view.storageDevices = devices.sorted(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
        }
    }
    
    /// 选择采集的设备
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDeviceHarvest device: Node) {
        
        let state = EnergyHarvestStateView(frame: UIScreen.main.bounds)
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                state.update(state: .connect)
            }
            Thread.sleep(forTimeInterval: 1.5)
            
            DispatchQueue.main.async {
                state.update(state: .inProgress(progress: 20, estimatedTime: "5 minutes"))
            }
            Thread.sleep(forTimeInterval: 1.5)
            DispatchQueue.main.async {
                if arc4random_uniform(2) == 1 {
                    state.update(state: .completed)
                }else {
                    state.update(state: .failure(message: "unstable_signal".localizedString))
                }
            }
        }
        state.show()
        harvestStateView = state
        
    }
    
}
