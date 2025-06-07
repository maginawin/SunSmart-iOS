//
//  EnergyHarvestHistoryViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/6.
//

import UIKit

class EnergyHarvestHistoryViewController: UIViewController {
    
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    private var selectCountLabel: UILabel!
    private var exportBtn: UIButton!
    private var deleteBtn: UIButton!
    
    private var selectDatas: [EnergyStatisticsStaticData] = []
    
    let space: SpaceData
    
    private var harvestDatas: [EnergyStatisticsStaticData] = []
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "harvest_history".localizedString
        
        view.backgroundColor = Background_Color
        
        harvestDatas = EnergyStatisticsStaticData.load(spaceId: space.id)
        
        setupUI()
        
        updateBottomUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        
        if harvestDatas.isEmpty { 
            bottomView.isHidden = true
            tableView.showEmptyDataView(title: "no_data".localizedString)
        }else {
            bottomView.isHidden = false
            tableView.hideEmptyDataView()
        }
    }
    
    /// 导出分享文件
    private func exportFiles(_ staticDatas: [EnergyStatisticsStaticData]) {
        
        var fileURLs: [URL] = []
        for staticData in staticDatas {
            var fileName = "\("static_data".localizedString) \(String.dateConvert(timestamp: "\(staticData.timestamp)", dateFormat: "M-d-yyyy hh:mm a"))"
            fileName = fileName.replacingOccurrences(of: ":", with: "_")
            guard let fileURL = staticData.convertingCVSFile(spaceName: space.name, fileName: fileName) else {
                XWHUDManager.showTipHUD("\(fileName) \("export_error".localizedString)", isLineFeed: true)
                return
            }
            fileURLs.append(fileURL)
        }
        let activityVc = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        // 适配 iPad
        if let popoverController = activityVc.popoverPresentationController {
            // 设置 sourceView（可以是按钮或视图）
            popoverController.sourceView = self.view
            // 设置 sourceRect（浮层的锚点位置）
            popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        activityVc.completionWithItemsHandler = {[weak self] (type, completion, _, error) in
            if completion {
                if error == nil {
                    XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                    self?.selectDatas.removeAll()
                    self?.updateBottomUI()
                    self?.tableView.reloadData()
                }else {
                    XWHUDManager.showSuccessTipHUD("failed".localizedString)
                }
                activityVc.dismiss(animated: true)
            }
        }
        self.present(activityVc, animated: true)
        
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            selectDatas = harvestDatas
        }else {
            selectDatas.removeAll()
        }
        tableView.reloadData()
        updateBottomUI()
    }
    
    @objc private func exportBtnAction() {
        guard selectDatas.count > 0 else {
            return
        }
        exportFiles(selectDatas)
    }
    
    @objc private func deleteBtnAction() {
        guard selectDatas.count > 0 else {
            return
        }
        harvestDatas.removeAll(where: { data in selectDatas.contains(where: { $0.timestamp == data.timestamp })  })
        // 删除文件
        selectDatas.forEach({
            $0.delete(spaceId: space.id)
        })
        selectDatas.removeAll()
        
        tableView.reloadData()
        updateBottomUI()
        updateEmptyUI()
        
        NotificationCenter.default.post(name: .init(energyStaticDataUpdateNotificationName), object: nil)
    }
    
    private func updateBottomUI() {
        
        selectAllBtn.isSelected = selectDatas.count == harvestDatas.count
        selectCountLabel.text = "\(selectDatas.count)/\(harvestDatas.count)"
        deleteBtn.isEnabled = selectDatas.count > 0
        exportBtn.isEnabled = selectDatas.count > 0
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        
        selectAllBtn = UIButton(normalImageName: "select_un", selectedImageName: "select", target: self, action: #selector(selectAllBtnAction))
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        bottomView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
        }
        
        selectCountLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        bottomView.addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllLabel)
            make.top.equalTo(selectAllLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
        exportBtn = UIButton(normalImageName: "energy_export", target: self, action: #selector(exportBtnAction))
        bottomView.addSubview(exportBtn)
        exportBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        deleteBtn = UIButton(normalImageName: "share_delete", target: self, action: #selector(deleteBtnAction))
        bottomView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(exportBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(exportBtn)
        }
        
        tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(EnergyHarvestHistoryViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.rowHeight = SCRYFrom(44)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }

}


extension EnergyHarvestHistoryViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return harvestDatas.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EnergyHarvestHistoryViewCell
        let data = harvestDatas[indexPath.row]
        cell.fileNameLabel.text = "\("static_data".localizedString) \(String.dateConvert(timestamp: "\(data.timestamp)", dateFormat: "M-d-yyyy hh:mm a"))"
        cell.isSelect = selectDatas.contains(where: { $0.timestamp == data.timestamp })
        cell.exportCallback = {[weak self] in
            // 导出单个数据
            self?.exportFiles([data])
        }
        cell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let fileData = harvestDatas[indexPath.row]
        if let index = selectDatas.firstIndex(where: { $0.timestamp == fileData.timestamp }) {
            selectDatas.remove(at: index)
        }else {
            selectDatas.append(fileData)
        }
        updateBottomUI()
        tableView.reloadData()
    }
    
}
