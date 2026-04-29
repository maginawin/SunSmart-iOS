//
//  LinkedEmerFireGroupSelectionVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import NordicSigMeshSDK

final class LinkedEmerFireGroupSelectionVC: UIViewController {

    private let groups: [Group]
    private var selectedGroupAddresses: [UInt16]
    private let disabledGroupAddresses: Set<UInt16>
    private let selectionHandler: ([UInt16]) -> Void
    private let bottomContainerHeight = SCRYFrom(72) + kSafeAreaBottomHeight

    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.backgroundColor = Background_Color
        tableView.register(SwitchSelectGroupsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.rowHeight = SCRYFrom(44)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()

    private lazy var selectAllBtn: UIButton = {
        let btn = UIButton(
            title: "select_all".localizedString,
            titleSize: 12,
            titleWeight: .light,
            titleColor: TextBlack_Color,
            normalImageName: "device_select_un",
            selectedImageName: "device_select",
            target: self,
            action: #selector(selectAllAction)
        )
        btn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        return btn
    }()

    private lazy var doneBtn: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = Bar_Color
        btn.layer.cornerRadius = SCRYFrom(22)
        btn.titleLabel?.font = FONTS(16)
        btn.setTitle("done".localizedString, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        return btn
    }()

    private lazy var bottomContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Background_Color
        return view
    }()

    init(
        groups: [Group],
        selectedGroupAddresses: [UInt16],
        disabledGroupAddresses: Set<UInt16>,
        selectionHandler: @escaping ([UInt16]) -> Void
    ) {
        self.groups = groups.sorted(by: { $0.address.address < $1.address.address })
        self.selectedGroupAddresses = selectedGroupAddresses.sorted()
        self.disabledGroupAddresses = disabledGroupAddresses
        self.selectionHandler = selectionHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "select_group(s)".localizedString
        view.backgroundColor = Background_Color
        setupNavigation()
        setupLayout()
        updateSelectAllState()

        if groups.isEmpty {
            view.showEmptyDataView(title: "no_groups".localizedString, tipText: "scene_not_groups_message".localizedString)
        }
    }

    private func setupNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: selectAllBtn)
    }

    private func setupLayout() {
        view.addSubview(bottomContainerView)
        bottomContainerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(bottomContainerHeight)
        }

        bottomContainerView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview().offset(SCRYFrom(10))
            make.height.equalTo(SCRYFrom(44))
        }

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomContainerView.snp.top)
        }
    }

    private func updateSelectAllState() {
        let selectableAddresses = selectableGroups.map(\.address.address)
        guard !selectableAddresses.isEmpty else {
            selectAllBtn.isSelected = false
            return
        }
        selectAllBtn.isSelected = Set(selectableAddresses).isSubset(of: Set(selectedGroupAddresses))
    }

    private var selectableGroups: [Group] {
        groups.filter { !disabledGroupAddresses.contains($0.address.address) || selectedGroupAddresses.contains($0.address.address) }
    }

    @objc private func selectAllAction(sender: UIButton) {
        sender.isSelected.toggle()

        if sender.isSelected {
            let addresses = selectableGroups.map { $0.address.address }
            selectedGroupAddresses = Array(Set(selectedGroupAddresses).union(addresses)).sorted()
        } else {
            selectedGroupAddresses.removeAll { address in
                selectableGroups.contains(where: { $0.address.address == address })
            }
        }

        tableView.reloadData()
    }

    @objc private func doneAction() {
        selectedGroupAddresses.sort()
        selectionHandler(selectedGroupAddresses)
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

extension LinkedEmerFireGroupSelectionVC: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SwitchSelectGroupsViewCell
        let group = groups[indexPath.row]
        let address = group.address.address
        let isSelected = selectedGroupAddresses.contains(address)
        let isDisabled = disabledGroupAddresses.contains(address) && !isSelected

        cell.selectionStyle = .none
        cell.nameLabel.text = group.name

        if isDisabled {
            cell.selectImageView.image = UIImage(named: isSelected ? "device_select_disable" : "device_select_un")?.withTintColor(RGB(216, 216, 216))
            cell.nameLabel.textColor = RGB(160, 160, 160)
        } else {
            cell.selectImageView.image = UIImage(named: isSelected ? "device_select" : "device_select_un")
            cell.nameLabel.textColor = TextBlack_Color
        }

        if group.nodes.isEmpty || !group.nodes.contains(where: { $0.state }) {
            cell.onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .normal)
        } else {
            cell.onoffBtn.setImage(UIImage(named: "scene_group_off"), for: .normal)
            cell.onoffBtn.isSelected = group.isOn
        }

        let isLast = indexPath.row == groups.count - 1
        cell.lineView.isHidden = isLast
        cell.configureCell(isFirst: indexPath.row == 0, isLast: isLast)
        cell.onOffCallback = { isOn in
            if group.nodes.count > 0 && group.nodes.contains(where: { $0.state }) {
                cell.onoffBtn.isSelected = isOn
                group.isOn = isOn
                MeshAPI.setGroupOnOffState(address: group.address.address, isOn: isOn)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let group = groups[indexPath.row]
        let address = group.address.address

        if disabledGroupAddresses.contains(address) && !selectedGroupAddresses.contains(address) {
            XWHUDManager.showTipHUD("Not selectable. This group is already associated with a device of the same type.", isLineFeed: true)
            return
        }

        if let index = selectedGroupAddresses.firstIndex(of: address) {
            selectedGroupAddresses.remove(at: index)
        } else {
            selectedGroupAddresses.append(address)
        }

        selectedGroupAddresses.sort()
        updateSelectAllState()
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
