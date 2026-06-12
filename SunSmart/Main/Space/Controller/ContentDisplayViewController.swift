//
//  ContentDisplayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/8.
//

import UIKit

class ContentDisplayViewController: UIViewController {

    enum Options {
        case deviceNameDisplay
        case cctQuickButtons
        case controlStyle

        var title: String {
            switch self {
            case .deviceNameDisplay:
                return "device_name_display".localizedString
            case .cctQuickButtons:
                return "cct_quick_buttons".localizedString
            case .controlStyle:
                return "control_style".localizedString
            }
        }

        var reuseIdentifier: String {
            switch self {
            case .deviceNameDisplay:
                return "deviceNameDisplayCell"
            case .cctQuickButtons:
                return "switchCell"
            case .controlStyle:
                return "controlStyleCell"
            }
        }
    }
    
    private var tableView: UITableView!
    private let options: [Options] = [.deviceNameDisplay, .cctQuickButtons, .controlStyle]

    private var isEditable: Bool {
        space.permission == .owner || space.permission == .editor
    }
        
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
        tableView.register(ContentDisplayViewCell.classForCoder(), forCellReuseIdentifier: Options.deviceNameDisplay.reuseIdentifier)
        tableView.register(ContentDisplaySwitchViewCell.classForCoder(), forCellReuseIdentifier: Options.cctQuickButtons.reuseIdentifier)
        tableView.register(ContentDisplayControlStyleViewCell.classForCoder(), forCellReuseIdentifier: Options.controlStyle.reuseIdentifier)
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

    private func notifyContentDisplayChanged() {
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.common
        )
    }

}

extension ContentDisplayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let option = options[indexPath.row]
        
        switch option {
        case .deviceNameDisplay:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplayViewCell
            cell.titleLabel.text = option.title
            cell.disableModeImageView.image = UIImage(named: "device_name_prefixes_hide")
            cell.enableModeImageView.image = UIImage(named: "device_name_prefixes_display")
            cell.note = "device_name_display_note".localizedString
            cell.optionsLabel.text = "display_device_name_prefix".localizedString
            cell.enableSwitch.isOn = space.displayDeviceNamePrefix
            cell.isEditable = isEditable
            cell.switchValueCallback = { [weak self] isOn in
                guard let self = self, self.isEditable else { return }
                guard self.space.displayDeviceNamePrefix != isOn else { return }
                self.space.displayDeviceNamePrefix = isOn
                self.notifyContentDisplayChanged()
            }
            return cell

        case .cctQuickButtons:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplaySwitchViewCell
            cell.titleLabel.text = option.title
            cell.note = "cct_quick_buttons_note".localizedString
            cell.optionTitle = "show_cct_quick_buttons".localizedString
            cell.isOn = space.showCCTQuickButtons
            cell.isEditable = isEditable
            cell.switchValueCallback = { [weak self] isOn in
                guard let self = self, self.isEditable else { return }
                guard self.space.showCCTQuickButtons != isOn else { return }
                self.space.showCCTQuickButtons = isOn
                self.notifyContentDisplayChanged()
            }
            return cell

        case .controlStyle:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplayControlStyleViewCell
            cell.titleLabel.text = option.title
            cell.note = "control_style_note".localizedString
            cell.selectedType = space.controlType
            cell.isEditable = isEditable
            cell.selectionCallback = { [weak self, weak cell] type in
                guard let self = self, self.isEditable else { return }
                guard self.space.controlType != type else { return }
                self.space.controlType = type
                cell?.selectedType = type
                self.notifyContentDisplayChanged()
            }
            return cell
        }
    }
    
}
