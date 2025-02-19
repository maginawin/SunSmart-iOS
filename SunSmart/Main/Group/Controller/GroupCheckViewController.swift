//
//  GroupCheckViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/15.
//

import UIKit
import NordicSigMeshSDK

class GroupCheckViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var functionView: GroupDevicesFunctionView!
    
    let nodes: [Node]
    let group: Group

    init(group: Group, nodes: [Node]) {
        self.group = group
        self.nodes = nodes
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        title = "check".localizedString
        setupUI()
    }
    
    private func setupUI() {
        
        functionView = GroupDevicesFunctionView()
        functionView.selectAllBtn.isHidden = true
        functionView.sortBtn.isHidden = true
//        functionView.checkBtn.isHidden = true
        functionView.delegate = self
        view.addSubview(functionView)
        functionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(14)
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(12), left: SCRXFrom(12), bottom: SCRYFrom(12), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        //        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(functionView.snp.top)
//            make.left.equalTo(SCRXFrom(30))
//            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo((navigationController?.navigationBar.frame.maxY ?? 0))
//            make.height.equalTo(SCRYFrom(340))
        }
    }
    

}

extension GroupCheckViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 6
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        cell.nameLabel.text = "ID001"
        cell.selectImageView.isHidden = false
        cell.selectImageView.image = UIImage(named: "sync_failed")
//        devices[indexPath.item]
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
}

extension GroupCheckViewController: GroupDevicesFunctionViewDelegate {
    
    func functionDidSyncDataAction(view: GroupDevicesFunctionView) {
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        
        let messageAttStr = NSMutableAttributedString(string: "device_configured_failed_title".localizedString, attributes: [.paragraphStyle: style, .foregroundColor: Title_Color])
        let noteAttStr = NSAttributedString(string: "device_configured_failed_note".localizedString, attributes: [.foregroundColor: RGB(100, 136, 139), .paragraphStyle: style])
        messageAttStr.append(noteAttStr)
        
        SRAlertView(title: "notification".localizedString, messageAttStr: messageAttStr, margin: SCRXFrom(27), actions: [SRAlertAction(title: "finish".localizedString, style: .cancel, actionHandler: nil), SRAlertAction(title: "re_sync".localizedString, actionHandler: { _ in
//            print("reconfigure")
            
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            
        })]).show()
        
    }
    
}
