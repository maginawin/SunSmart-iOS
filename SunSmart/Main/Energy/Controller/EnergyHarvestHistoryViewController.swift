//
//  EnergyHarvestHistoryViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/6.
//

import UIKit

class EnergyHarvestHistoryViewController: UIViewController {

    struct FileData {
        let id: String
        let name: String
        let data: Data
    }
    
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    private var selectCountLabel: UILabel!
    private var exportBtn: UIButton!
    private var deleteBtn: UIButton!
    
    private var selectFiles: [FileData] = []
    
    private var files: [FileData] = [
        FileData(id: UUID().uuidString, name: "Static Data 2-18-2025 10:30 PM", data: Data()),
        FileData(id: UUID().uuidString, name: "Static Data 3-18-2025 10:30 PM", data: Data()),
        FileData(id: UUID().uuidString, name: "Static Data 4-18-2025 10:30 PM", data: Data())
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "harvest_history".localizedString
        
        view.backgroundColor = Background_Color
        setupUI()
        
        updateBottomUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if files.isEmpty {
            bottomView.isHidden = true
            tableView.showEmptyDataView(title: "no_data".localizedString)
        }
        
    }
    
    private func exportFiles(_ files: [FileData]) {
        
        
        
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            selectFiles = files
        }else {
            selectFiles.removeAll()
        }
        tableView.reloadData()
        updateBottomUI()
    }
    
    @objc private func exportBtnAction() {
        guard selectFiles.count > 0 else {
            return
        }
        exportFiles(selectFiles)
    }
    
    @objc private func deleteBtnAction() {
        guard selectFiles.count > 0 else {
            return
        }
        // 删除文件
        
        
        
    }
    
    private func updateBottomUI() {
        
        selectAllBtn.isSelected = selectFiles.count == files.count
        selectCountLabel.text = "\(selectFiles.count)/\(files.count)"
        deleteBtn.isEnabled = selectFiles.count > 0
        exportBtn.isEnabled = selectFiles.count > 0
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
        return files.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EnergyHarvestHistoryViewCell
        let fileData = files[indexPath.row]
        cell.fileNameLabel.text = fileData.name
        cell.isSelect = selectFiles.contains(where: { $0.id == fileData.id })
        cell.exportCallback = {[weak self] in
            // 导出单个数据
            self?.exportFiles([fileData])
        }
        cell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let fileData = files[indexPath.row]
        if let index = selectFiles.firstIndex(where: { $0.id == fileData.id }) {
            selectFiles.remove(at: index)
        }else {
            selectFiles.append(fileData)
        }
        updateBottomUI()
        tableView.reloadData()
    }
    
}
