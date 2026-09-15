//
//  ScenesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/22.
//

import UIKit
import NordicSigMeshSDK

class ScenesViewCell: GroupsViewCell {
    
    /// 场景执行动画view
    private var animationView: SceneExecuteAnimationView!
    private var sceneRequestID = UUID()
    
    /// 是否执行中
    var isExecuting: Bool {
        return animationView.animation
    }
    
    var scene: Scene! {
        didSet {
            let imageIndex = max(min(scene.info.imageId, sceneImageNames.count) - 1, 0)
            self.imageView.image = UIImage(named: sceneImageNames[imageIndex])
            self.nameLabel.text = scene.name
            
            sceneRequestID = UUID()
            let requestID = sceneRequestID
            // Pending and unavailable status must not look authoritatively synced.
            imageView.image = UIImage(named: "sync_failed_big")
            NodeSyncStatusRefresh.request(scene: scene, owner: self) { [weak self] needsSync in
                guard let self, self.sceneRequestID == requestID else { return }
                self.imageView.image = UIImage(named: needsSync ? "sync_failed_big" : sceneImageNames[imageIndex])
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sceneRequestID = UUID()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        animationView = SceneExecuteAnimationView()
        contentView.addSubview(animationView)
        animationView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView.bringSubviewToFront(deleteBtn)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 开始执行场景动画
    func showExecuteAnimation() {
        animationView.startAnimation()
    }
    
}
