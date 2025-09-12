//
//  ContentDisplayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/8.
//

import UIKit

class ContentDisplayViewController: UIViewController {

    enum Options {
        /// 标题、禁用后图片、启用后图片、描述、功能标题
        var data: (title: String, hideImageName: String, displayImageName: String, note: String, content: String) {
            switch self {
            case .deviceNameDisplay:
                return ("device_name_display".localizedString, "device_name_prefixes_hide", "device_name_prefixes_display", "device_name_display_note".localizedString, "display_device_name_prefix".localizedString)
            }
        }
        
        case deviceNameDisplay
    }
    
    private var tableView: UITableView!
    private let options: [Options] = [.deviceNameDisplay]
        
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

        title = "content_display".localizedString
        
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        setupUI()
    }
    
    @objc private func back() {
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        }else {
            dismiss(animated: true)
        }
    }
    
    private func setupUI() {
        
        tableView = UITableView()
        tableView.backgroundColor = Background_Color
        tableView.register(ContentDisplayViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = UITableView.automaticDimension
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(7))
            make.left.right.bottom.equalToSuperview()
        }
        
    }

}

extension ContentDisplayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let option = options[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! ContentDisplayViewCell
        
        let data = option.data
        cell.titleLabel.text = data.title
        cell.disableModeImageView.image = UIImage(named: data.hideImageName)
        cell.enableModeImageView.image = UIImage(named: data.displayImageName)
        cell.note = data.note
        cell.optionsLabel.text = data.content
        
        switch option {
        case .deviceNameDisplay:
            cell.enableSwitch.isOn = space.displayDeviceNamePrefix
            cell.switchValueCallback = {[weak self] isOn in
                guard let self = self else { return }
                self.space.displayDeviceNamePrefix = isOn
                self.space.save()
            }
        }
        return cell
    }
    
}
