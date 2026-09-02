//
//  GroupPathSequenceQuickAddView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

/// 快速添加状态
enum QuickAddState {
    /// 添加中
    case adding
    /// 暂停
    case pause
    /// 停止
    case stop
}

protocol GroupPathSequenceQuickAddViewDelegate: AnyObject {
    
    /// 快速添加状态更新
    func quickAddView(_ view: GroupPathSequenceQuickAddView, addStateChanged addState: QuickAddState)
    
    /// 快速添加是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func quickAddView(_ view: GroupPathSequenceQuickAddView, showAddedDevicesChanged showAdded: Bool)
}


class GroupPathSequenceQuickAddView: UIView {
    private let topContentInset: CGFloat = 8
    private let spacePreferredContentHeight: CGFloat = 186
    private let spaceControlCenterYOffset: CGFloat = 20
    
    private var helpImageView: UIImageView!
    private var groupFilterView: UIView!
    private var groupTitleLabel: UILabel!
    private var groupArrowImageView: UIImageView!
    private var titleLabel: UILabel!
    var addView: UIView!
    private var addTypeView: UIView!
    private var arrowImageView: UIImageView!
    private var startBtn: UIButton!
    private var stopBtn: UIButton!
//    private var pauseBtn: UIButton!
    private var addStateLabel: UILabel!
    private var hintLabel: UILabel!
    private var messageLabel: UILabel!
    
    var guideContentView: UIView!
    var guideView: GroupPathSequenceDeviceAddStepView!
    
    var showAdded: Bool = false
    var isSequence: Bool = true
    var groupFilterChanged: ((Int) -> Void)?
    weak var delegate: GroupPathSequenceQuickAddViewDelegate?
    private var groupFilterTitles: [String] = []
    private var groupFilterEnabledStates: [Bool] = []
    private var groupFilterSelectedIndex: Int = 0
    private var usesDualFilterLayout: Bool = false

    private var guidePreferredContentHeight: CGFloat {
        let fallbackWidth = SCREEN_WIDTH - 48
        let fittingWidth = max((bounds.width > 0 ? bounds.width : fallbackWidth) - 16, 200)
        return max(68, guideView.preferredHeight(fittingWidth: fittingWidth) + 24)
    }

    var preferredContentHeight: CGFloat {
        if !guideContentView.isHidden {
            return guidePreferredContentHeight
        }
        return usesDualFilterLayout ? spacePreferredContentHeight : 130
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 展示流程UI
    func showStepGuideUI() {
        guideContentView.isHidden = false
        addView.isHidden = true
        stopBtn.isHidden = true
        updateSpaceContentVisibility()
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview()
        }
    }
    
    /// 更新快速添加状态
    func updateQuickAddState(_ state: QuickAddState) {
        guideContentView.isHidden = true
        addView.isHidden = false
        updateSpaceContentVisibility()
        switch state {
        case .adding:
            stopBtn.isHidden = false
            addStateLabel.text = "Adding…".localizedString
            addStateLabel.textColor = Green_Color
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview().offset(-40)
            }
            startBtn.isSelected = true
        case .pause:
            stopBtn.isHidden = false
            addStateLabel.text = "pause_add".localizedString
            addStateLabel.textColor = Red_Color
            startBtn.isSelected = true
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview().offset(-40)
            }
            
        case .stop:
            addStateLabel.text = "click_to_start".localizedString
            addStateLabel.textColor = ImportantText_Color
            stopBtn.isHidden = true
            startBtn.isSelected = false
            startBtn.snp.updateConstraints { make in
                make.centerX.equalToSuperview()
            }
        }
    }

    private func updateSpaceContentVisibility() {
        let shouldShowSpaceContent = usesDualFilterLayout && guideContentView.isHidden
        groupFilterView.isHidden = !shouldShowSpaceContent
        hintLabel.isHidden = !shouldShowSpaceContent
    }

    private func updateAddControlCenterY() {
        let centerYOffset = usesDualFilterLayout ? spaceControlCenterYOffset : 0
        startBtn.snp.updateConstraints { make in
            make.centerY.equalToSuperview().offset(centerYOffset)
        }
    }
    
    @objc private func startBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            addStateLabel.text = "Adding…".localizedString
            addStateLabel.textColor = Green_Color
        }else {
            addStateLabel.text = "pause_add".localizedString
            addStateLabel.textColor = Red_Color
        }
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview().offset(-40)
        }
        
        stopBtn.isHidden = false
        delegate?.quickAddView(self, addStateChanged: sender.isSelected ? .adding : .pause)
    }
    
    @objc private func stopBtnAction() {
        stopBtn.isHidden = true
        
        startBtn.isSelected = false
        startBtn.isHidden = false
        startBtn.snp.updateConstraints { make in
            make.centerX.equalToSuperview()
        }
        addStateLabel.text = "click_to_start".localizedString
        addStateLabel.textColor = ImportantText_Color
        delegate?.quickAddView(self, addStateChanged: .stop)
    }

    @objc private func helpImageAction() {
        GroupPathSequenceAddDescriptionController.push(mode: .quickAdd, isSequence: isSequence)
    }
    
    @objc private func addTypeSelectAction() {
        var menuWidth: CGFloat = isIPad ? 300 : 256
        var menuTitles = ["quick_add_ignore_added_devices".localizedString, "quick_add_show_added_devices".localizedString]
        var selectedTitles = menuTitles
        if usesDualFilterLayout {
            menuTitles = ["quick_add_ignore_added_devices".localizedString, "trigger_add_show_added_devices".localizedString]
            selectedTitles = ["space_trigger_zone_new_only".localizedString, "space_trigger_zone_used".localizedString]
            menuWidth = isIPad ? 320 : 256
        } else if !isSequence {
            menuTitles = ["quick_add_ignore_added_devices".localizedString, "zone_quick_add_show_added_devices".localizedString]
            selectedTitles = menuTitles
            menuWidth += 14
        }
        let btnPoint = CGPoint(x: addTypeView.frame.maxX - menuWidth, y: addTypeView.frame.maxY + 4)
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())

//        if usesDualFilterLayout {
            TitleSelectView.show(titles: menuTitles,
                                 style: .default,
                                 anchorPoint: windowPoint,
                                 selectIndex: showAdded ? 1 : 0,
                                 menuWidth: menuWidth,
                                 itemHeight: 30,
                                 titleColor: RGB(100, 116, 139),
                                 titleFont: UIFont.systemFont(ofSize: 12, weight: .regular),
                                 backgroundColor: .white,
                                 selectBackgroundColor: Bar_Color.withAlphaComponent(0.12),
                                 selectedTitleColor: Bar_Color,
                                 highlightSelectedWithoutIcon: true,
                                 titleAlignment: .left,
                                 contentBorderColor: RGB(236, 236, 236),
                                 contentBorderWidth: 1,
                                 contentCornerRadius: 10,
                                 rowHighlightInsets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4),
                                 rowHighlightCornerRadius: 5) {[weak self] index in
                guard let self = self else { return }
                self.titleLabel.text = selectedTitles[index]
                self.showAdded = index == 1
                self.delegate?.quickAddView(self, showAddedDevicesChanged: self.showAdded)
            }
//            return
//        }
//
//        TitleSelectView.show(titles: menuTitles, style: .default, anchorPoint: windowPoint, menuWidth: menuWidth, itemHeight: 44, titleFont: UIFont.systemFont(ofSize: 14, weight: .light)) {[weak self] index in
//            guard let self = self else { return }
//            self.titleLabel.text = selectedTitles[index]
//            
//            self.showAdded = index == 1
//            self.delegate?.quickAddView(self, showAddedDevicesChanged: self.showAdded)
//        }
        
    }

    @objc private func groupFilterSelectAction() {
        guard usesDualFilterLayout, !groupFilterTitles.isEmpty else {
            return
        }
        let menuWidth = groupFilterView.bounds.width > 0 ? groupFilterView.bounds.width : 186
        let btnPoint = CGPoint(x: groupFilterView.frame.maxX - menuWidth, y: groupFilterView.frame.maxY + 4)
        let windowPoint = self.convert(btnPoint, to: UIApplication.shared.keyWindow())
        
        TitleSelectView.show(titles: groupFilterTitles,
                             style: .default,
                             anchorPoint: windowPoint,
                             selectIndex: groupFilterSelectedIndex,
                             menuWidth: menuWidth,
                             itemHeight: 30,
                             titleColor: RGB(100, 116, 139),
                             titleFont: UIFont.systemFont(ofSize: 12, weight: .regular),
                             backgroundColor: .white,
                             selectBackgroundColor: Bar_Color.withAlphaComponent(0.12),
                             enabledStates: groupFilterEnabledStates,
                             disabledTitleColor: RGB(100, 116, 139, 0.5),
                             selectedTitleColor: Bar_Color,
                             highlightSelectedWithoutIcon: true,
                             titleAlignment: .left,
                             contentBorderColor: RGB(236, 236, 236),
                             contentBorderWidth: 1,
                             contentCornerRadius: 10,
                             rowHighlightInsets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4),
                             rowHighlightCornerRadius: 5) { [weak self] index in
            guard let self else { return }
            self.groupFilterSelectedIndex = index
            self.groupTitleLabel.text = self.groupFilterTitles[index]
            self.groupFilterChanged?(index)
        }
    }

    func configureDefaultQuickAdd() {
        usesDualFilterLayout = false
        groupFilterTitles.removeAll()
        groupFilterEnabledStates.removeAll()
        groupFilterSelectedIndex = 0
        showAdded = false
        titleLabel.text = "quick_add_ignore_added_devices".localizedString
        hintLabel.text = nil
        messageLabel.text = "path_quick_add_message".localizedString
        updateSpaceContentVisibility()
        updateAddControlCenterY()
        addTypeView.snp.remakeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(6)
            make.top.equalTo(topContentInset)
            make.height.equalTo(30)
            make.right.equalTo(-16)
        }
    }

    func configureSpaceTriggerZoneQuickAdd(groupTitles: [String], enabledStates: [Bool], selectedGroupIndex: Int, showAddedOnly: Bool) {
        usesDualFilterLayout = true
        groupFilterTitles = groupTitles
        groupFilterEnabledStates = enabledStates
        groupFilterSelectedIndex = max(0, min(selectedGroupIndex, max(groupTitles.count - 1, 0)))
        groupTitleLabel.text = groupFilterTitles.isEmpty ? nil : groupFilterTitles[groupFilterSelectedIndex]
        showAdded = showAddedOnly
        titleLabel.text = showAddedOnly ? "space_trigger_zone_used".localizedString : "space_trigger_zone_new_only".localizedString
        hintLabel.text = "space_trigger_zone_quick_add_hint".localizedString
        messageLabel.text = "space_trigger_zone_quick_add_message".localizedString
        updateSpaceContentVisibility()
        updateAddControlCenterY()
        addTypeView.snp.remakeConstraints { make in
            make.left.equalTo(groupFilterView.snp.right).offset(8)
            make.top.equalTo(topContentInset)
            make.height.equalTo(30)
            make.width.equalTo(90)
            make.right.lessThanOrEqualTo(-16)
        }
    }
    
    private func setupUI() {
        
        addView = UIView()
        addSubview(addView)
        addView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        helpImageView = UIImageView(image: UIImage(named: "help"))
        helpImageView.isUserInteractionEnabled = true
        helpImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(helpImageAction)))
        addView.addSubview(helpImageView)
        helpImageView.snp.makeConstraints { make in
            make.left.equalTo(8)
            make.top.equalTo(topContentInset)
            make.width.height.equalTo(30)
        }

        groupFilterView = UIView()
        groupFilterView.isHidden = true
        groupFilterView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(groupFilterSelectAction)))
        groupFilterView.layer.cornerRadius = 10
        groupFilterView.layer.borderWidth = 1
        groupFilterView.layer.borderColor = Border_Color.cgColor
        groupFilterView.backgroundColor = .white
        addView.addSubview(groupFilterView)
        groupFilterView.snp.makeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(6)
            make.top.equalTo(topContentInset)
            make.height.equalTo(30)
            make.width.equalTo(186)
        }

        groupArrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        groupFilterView.addSubview(groupArrowImageView)
        groupArrowImageView.snp.makeConstraints { make in
            make.right.equalTo(-8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }

        groupTitleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 13, fontWeight: .light, fit: false)
        groupFilterView.addSubview(groupTitleLabel)
        groupTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(12)
            make.centerY.equalToSuperview()
            make.right.equalTo(groupArrowImageView.snp.left).offset(-8)
        }

        addTypeView = UIView()
        addTypeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addTypeSelectAction)))
        addTypeView.layer.cornerRadius = 10
        addTypeView.layer.borderWidth = 1
        addTypeView.layer.borderColor = Border_Color.cgColor
        addTypeView.backgroundColor = .white
        addView.addSubview(addTypeView)
        addTypeView.snp.makeConstraints { make in
            make.left.equalTo(helpImageView.snp.right).offset(6)
            make.top.equalTo(topContentInset)
            make.height.equalTo(30)
            make.right.equalTo(-16)
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        addTypeView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(-12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
        
        titleLabel = UILabel(text: "quick_add_ignore_added_devices".localizedString, textColor: TextBlack_Color, fontSize: 13, fontWeight: .light, fit: false)
        addTypeView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(12)
            make.centerY.equalToSuperview()
            make.right.equalTo(arrowImageView.snp.left).offset(-12)
        }

        hintLabel = UILabel(text: nil, textColor: AssistText_Color, fontSize: 12, fontWeight: .light, fit: false)
        hintLabel.isHidden = true
        hintLabel.numberOfLines = 2
        hintLabel.textAlignment = .center
        addView.addSubview(hintLabel)
        hintLabel.snp.makeConstraints { make in
            make.left.equalTo(14)
            make.right.equalTo(-14)
            make.top.equalTo(addTypeView.snp.bottom).offset(8)
        }
        
        startBtn = UIButton(normalImageName: "quick_add_start", selectedImageName: "quick_add_pause", target: self, action: #selector(startBtnAction))
        addView.addSubview(startBtn)
        startBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        
//        pauseBtn = UIButton(normalImageName: "quick_add_pause", target: self, action: #selector(startBtnAction))
//        pauseBtn.isHidden = true
//        addView.addSubview(pauseBtn)
//        pauseBtn.snp.makeConstraints { make in
//            make.right.equalTo(addView.snp.centerX).offset(-20)
//            make.top.equalTo(startBtn)
//        }
        
        stopBtn = UIButton(normalImageName: "quick_add_stop", target: self, action: #selector(stopBtnAction))
        stopBtn.isHidden = true
        addView.addSubview(stopBtn)
        stopBtn.snp.makeConstraints { make in
            make.left.equalTo(addView.snp.centerX).offset(20)
            make.centerY.equalTo(startBtn)
        }
        
        addStateLabel = UILabel(text: "click_to_start".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        addStateLabel.textColor = ImportantText_Color
        addView.addSubview(addStateLabel)
        addStateLabel.snp.makeConstraints { make in
            make.right.equalTo(-16)
            make.centerY.equalTo(startBtn)
        }
        
        messageLabel = UILabel(text: "path_quick_add_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 2
        messageLabel.textAlignment = .center
        addView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(15)
            make.right.equalTo(-13)
            make.bottom.equalTo(-6)
        }
        
        guideContentView = UIView()
        guideContentView.backgroundColor = .clear
        guideContentView.isHidden = true
        addSubview(guideContentView)
        guideContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        guideView = GroupPathSequenceDeviceAddStepView(frame: .zero, steps: [
            .init(imageName: "proximity_lighting_step1", title: "quick_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "quick_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "quick_add_step3".localizedString, textColor: SubText_Color)
        ], layoutStyle: .equalColumns)
        guideContentView.addSubview(guideView)
        guideView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureDefaultQuickAdd()
    }
    
}
