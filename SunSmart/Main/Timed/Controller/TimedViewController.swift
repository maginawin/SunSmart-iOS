//
//  TimedViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit
import NordicSigMeshSDK

class TimedViewController: UIViewController {

    /// 底部
    private var footerView: SpaceFunctionFooterView!
    private var scheduleFlowLayout: UICollectionViewFlowLayout!
    private var scheduleCollectionView: UICollectionView!
    private var selectTypeView: TimedSelectTypeView!
    
    private var schedules: [Schedule] = []
    
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
        setupUI()
        
        let actions: [SchedulerAction] = [.turnOn, .turnOff, .sceneRecall]
        
        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        
        let workdays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday]
        
        let weekends: [WeekDay] = [.Saturday, .Sunday]
        
        let irregularity: [WeekDay] = [.Monday, .Wednesday, .Saturday]
        
        let randomWeeks = [allWeekDays, workdays, weekends, irregularity]
        
        let create = "\(CLongLong(Date().timeIntervalSince1970 * 1000))"
        for i in 1...4 {
            let actionIndex = arc4random_uniform(UInt32(actions.count))
            let weekIndex = arc4random_uniform(UInt32(randomWeeks.count))
            
            let schedule = Schedule(id: i, name: "Schedule \(i)", enabled: i < 3, action: actions[Int(actionIndex)], fadeTime: 5, weekDays: randomWeeks[Int(weekIndex)], hour: Int(arc4random_uniform(24)), minute: 0, create: create)
            schedules.append(schedule)
        }
        
        footerView.countBtn.setTitle("\(schedules.count)/16", for: .normal)
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        
        if schedules.isEmpty {
            scheduleCollectionView.showEmptyDataView(title: "no_schedules".localizedString, tipText: "no_schedules_message".localizedString, position: .center, bottomMargin: SCRYFit(27))
        }else {
            scheduleCollectionView.hideEmptyDataView()
        }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.editBtn.isHidden = true
        footerView.sortBtn.isHidden = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(44))
        }
        
        selectTypeView = TimedSelectTypeView()
        selectTypeView.delegate = self
        view.addSubview(selectTypeView)
        selectTypeView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(106))
            make.bottom.equalTo(footerView.snp.top)
        }
        
        view.sendSubviewToBack(selectTypeView)
        
        scheduleFlowLayout = UICollectionViewFlowLayout()
        scheduleFlowLayout.minimumLineSpacing = SCRXFrom(16)
        scheduleFlowLayout.minimumInteritemSpacing = 0
        
        scheduleCollectionView = UICollectionView(frame: .zero, collectionViewLayout: scheduleFlowLayout)
        scheduleCollectionView.showsVerticalScrollIndicator = false
        scheduleCollectionView.backgroundColor = .clear
        scheduleCollectionView.alwaysBounceVertical = true
        scheduleCollectionView.dataSource = self
        scheduleCollectionView.delegate = self
        scheduleCollectionView.register(SchedulesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        scheduleCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        view.addSubview(scheduleCollectionView)
        scheduleCollectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(selectTypeView.snp.top)
        }
        
    }

}

extension TimedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return schedules.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SchedulesViewCell
        let schedule = schedules[indexPath.item]
        cell.schedule = schedule
        cell.enabledActionCallback = {[weak self] enabled in
            
            XWHUDManager.showCustomHUD(withMessage: "processing".localizedString, isWindow: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                schedule.enabled = enabled
                collectionView.reloadItems(at: [indexPath])
            }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let schedule = schedules[indexPath.item]
        
        return CGSize(width: itemW, height: schedule.enabled ? SCRYFrom(114) : SCRYFrom(64))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let schedule = schedules[indexPath.item]
        
    }
}

extension TimedViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
    }
}

extension TimedViewController: TimedSelectTypeViewDelegate {
    
    /// 选择类型
    func view(_ view: TimedSelectTypeView, selectTypeAction tyoe: TimedSelectTypeView.TimedType) {
        
        scheduleCollectionView.isHidden = tyoe != .schedule
        
    }
}
