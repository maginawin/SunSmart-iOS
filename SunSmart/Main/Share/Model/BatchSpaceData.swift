//
//  BatchSpaceData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/27.
//

import Foundation

/// 批量分享space数据
class BatchSpaceData {
    /// 所属site id
    let siteId: String
    /// 分享的邀请码
    let code: String
    /// 批量分享的名称
    let name: String
    /// 分享的space list
    let spaces: [SpaceData]
    /// 编辑者密码
    var editorPassword: String
    
    init(siteId: String, code: String, name: String, spaces: [SpaceData], editorPassword: String) {
        self.siteId = siteId
        self.code = code
        self.name = name
        self.spaces = spaces
        self.editorPassword = editorPassword
    }
}


class BatchSpaceImportResult {
    
    /// 导入space状态
    enum Status: Int {
        
        var rawString: String {
            switch self {
            case .successfully:
                return "successfully_improrted".localizedString
            case .presenceEditor:
                return "presence_editor".localizedString
            case .invalid:
                return "invalid".localizedString
            case .alreadyExist:
                return "already_exist".localizedString
            }
        }
        
        /// 成功
        case successfully = 1
        /// 存在editor
        case presenceEditor = 2
        /// 已存在space
        case alreadyExist = 3
        /// 无效（space已删除等）
        case invalid = 4
    }
    
    /// space id
    let spaceId: String
    /// space名称
    let spaceName: String
    /// 编辑者密码
    let editorPassword: String?
    /// 导入状态
    let status: Status
    
    init(spaceId: String, spaceName: String, editorPassword: String?, status: Status) {
        self.spaceId = spaceId
        self.spaceName = spaceName
        self.editorPassword = editorPassword
        self.status = status
    }
}
