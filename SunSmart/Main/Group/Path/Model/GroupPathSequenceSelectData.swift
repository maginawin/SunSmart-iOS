//
//  GroupPathSequenceSelectData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/20.
//

import Foundation

/// 方向
enum PathDirection {
    /// 向右
    case right
    /// 向左
    case left
}

class GroupPathSequenceSelectData {
    
    /// 选中path 
    var path: GroupProximityLightingSequencePath?
    /// 选中item
    var item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem?
    /// 方向
    var direction: PathDirection = .right
    
    /// 是否选中
    var isSelect: Bool {
        return path != nil && item != nil
    }
}
