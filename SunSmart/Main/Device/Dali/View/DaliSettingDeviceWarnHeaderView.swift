//
//  DaliSettingDeviceWarnHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/27.
//

import UIKit

class DaliSettingDeviceWarnHeaderView: UITableViewHeaderFooterView {

    private var tableView: UITableView!
    var warns: [ScanDaliDevicesWarn] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .white
        
        tableView = UITableView()
        tableView.rowHeight = SCRYFrom(44)
        tableView.separatorStyle = .none
        tableView.register(DaliSettingDeviceWarnViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        contentView.addSubview(tableView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension DaliSettingDeviceWarnHeaderView: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return warns.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DaliSettingDeviceWarnViewCell
        cell.titleLabel.text = warns[indexPath.row].title
        return cell
    }
    
}

class DaliSettingDeviceWarnViewCell: UITableViewCell {
    
    private var bgView: UIView!
    var titleLabel: UILabel!
    var warnImageView: UIImageView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = UIColor.red.withAlphaComponent(0.05)
        bgView.layer.cornerRadius = 7
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(8))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        titleLabel = UILabel(text: "", textColor: Red_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-40))
        }
        
        warnImageView = UIImageView(image: UIImage(named: "warn"))
        bgView.addSubview(warnImageView)
        warnImageView.snp.makeConstraints { make in
            make.centerY.right.equalToSuperview()
        }
        
    }
    
}
