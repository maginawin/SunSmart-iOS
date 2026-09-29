//
//  BatchSpaceData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/27.
//

import Foundation

/// Reclaim results and readbacks belong to a Space, never just to an editor ID.
@MainActor
enum SpaceEditorReclaim {
    enum Outcome: Equatable { case cleared, busy, failed, unconfirmed, changed }
    private struct Target {
        let space: SpaceData
        let scope: SpaceMembershipRecord.Scope
        let editorID: String?
        let storedEditorID: String?
        let generation: UUID
    }
    private enum EditorReadback { case absent, member(UserData) }
    private static var generations: [SpaceMembershipRecord.Scope: UUID] = [:]

    static func clear(spaces: [SpaceData], single: Bool = false) async -> [Outcome] {
        guard let first = spaces.first, !single || spaces.count == 1,
              spaces.allSatisfy({ $0.siteId == first.siteId && $0.permission == .owner }) else { return [.changed] }
        let context = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        let targets = spaces.map { space -> Target in
            let scope = SpaceMembershipCoordinator.scope(space)
            let generation = UUID()
            generations[scope] = generation
            return Target(space: space, scope: scope, editorID: space.editor?.uuid,
                storedEditorID: SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.editor?.uuid,
                generation: generation)
        }
        defer {
            for target in targets where generations[target.scope] == target.generation {
                generations.removeValue(forKey: target.scope)
            }
        }
        let api: NetowrkReqeustApi
        if single {
            guard let editorID = targets[0].editorID else { return [.unconfirmed] }
            api = .clearSpaceMember(siteId: first.siteId, spaceId: first.id, userId: editorID, permission: .editor, force: false)
        } else {
            api = .clearSpacesMembers(siteId: first.siteId, spaces: spaces.map(\.id), permission: .editor, force: false)
        }
        guard targets.allSatisfy({ current($0, context: context) != nil }) else { return [.changed] }
        let response = await NetworkRequest.shared.request(api)
        var outcomes: [Outcome] = []
        for target in targets {
            guard current(target, context: context) != nil else { outcomes.append(.changed); continue }
            let code = reclaimCode(response, spaceID: target.space.id, editorID: target.editorID, single: single)
            // Read metadata only: do not make membership confirmation depend on Mesh import.
            let members = await NetworkRequest.shared.request(.spaceMembers(siteId: target.scope.siteID, spaceId: target.scope.spaceID))
            guard current(target, context: context) != nil else { outcomes.append(.changed); continue }
            var editor = readback(members, spaceID: target.scope.spaceID, completeSpace: false)
            if editor == nil {
                // Older member endpoints may omit editor. A complete owner GET has
                // the same absent-editor semantics as applyRemoteSpaceMetadata.
                let info = await NetworkRequest.shared.request(.spaceInfo(siteId: target.scope.siteID,
                    spaceId: target.scope.spaceID, password: target.space.authorizationPassword))
                guard current(target, context: context) != nil else { outcomes.append(.changed); continue }
                editor = readback(info, spaceID: target.scope.spaceID, completeSpace: true)
            }
            guard let editor, let latest = current(target, context: context) else {
                outcomes.append(code == NetworkApiError.editorBeingUsedSpace.code ? .busy : .unconfirmed)
                continue
            }
            let member: UserData?
            switch editor {
            case .absent: member = nil
            case .member(let value): member = value
            }
            // Save the freshly loaded row so unrelated configuration changes survive.
            latest.editor = member
            guard latest.save() else { outcomes.append(.unconfirmed); continue }
            target.space.editor = member
            let outcome: Outcome
            if code == NetworkApiError.editorBeingUsedSpace.code { outcome = .busy }
            else if let code, code != 200 { outcome = .failed }
            else { outcome = member == nil ? .cleared : .unconfirmed }
            outcomes.append(outcome)
            #if DEBUG
            print("[SpaceEditorReclaim] space=\(target.scope.spaceID) code=\(code.map(String.init) ?? "unknown") outcome=\(outcome)")
            #endif
        }
        return outcomes
    }

    private static func current(_ target: Target, context: [String: String]) -> SpaceData? {
        guard !Task.isCancelled,
              SpaceMembershipResponseContext.matches(context, account: UserData.currentUserId,
                region: String(describing: UserData.currentServerRegion)),
              generations[target.scope] == target.generation,
              target.space.siteId == target.scope.siteID, target.space.id == target.scope.spaceID,
              target.space.permission == .owner, target.space.state == .normal,
              target.space.editor?.uuid == target.editorID,
              !SpaceMembershipCoordinator.isLeaving(target.space),
              let latest = SpaceData.load(siteId: target.scope.siteID, spaceId: target.scope.spaceID).first,
              latest.permission == .owner, latest.state == .normal,
              latest.editor?.uuid == target.storedEditorID else { return nil }
        return latest
    }

    private static func reclaimCode(_ result: Result<[String: Any], NetworkApiError>,
                                    spaceID: String, editorID: String?, single: Bool) -> Int? {
        switch result {
        case .failure(let error): return error.code
        case .success(let response):
            if single { return 200 }
            guard let data = response["data"] as? [String: Any],
                  let detail = data["detail"] as? [String: Any],
                  let results = detail[spaceID] as? [String: Int], !results.isEmpty else { return nil }
            if let editorID { return results[editorID] }
            // A stale cache may not yet know the editor being reclaimed.
            return results.values.first(where: { $0 != 200 }) ?? 200
        }
    }

    private static func readback(_ result: Result<[String: Any], NetworkApiError>,
                                 spaceID: String, completeSpace: Bool) -> EditorReadback? {
        guard case .success(let response) = result, let data = response["data"] as? [String: Any] else { return nil }
        let payload = completeSpace ? data : (data["space"] as? [String: Any] ?? data)
        if let id = payload["uuid"] as? String, id != spaceID { return nil }
        if completeSpace {
            guard payload["uuid"] as? String == spaceID, payload["role"] as? String == "owner",
                  SpaceMembershipCoordinator.accepts(payload) else { return nil }
        }
        guard let raw = payload["editor"] else { return completeSpace ? .absent : nil }
        if raw is NSNull { return .absent }
        guard let object = raw as? [String: Any] else { return nil }
        if object.isEmpty { return .absent }
        guard let id = object["userId"] as? String, !id.isEmpty,
              let name = object["username"] as? String else { return nil }
        return .member(UserData(name: name, uuid: id))
    }
}

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
                return "successful".localizedString
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
