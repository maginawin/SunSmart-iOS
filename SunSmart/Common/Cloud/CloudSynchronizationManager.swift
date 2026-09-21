//
//  CloudSynchronizationManager.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/15.
//

import Foundation
import Moya
import NordicSigMeshSDK
import SwiftyJSON
import UIKit

/// 操作类型
enum SyncOperation {
    
//    var target: NetowrkReqeustApi {
//        switch self {
//        case .syncSite(let site):
//            return .siteUpload(site: site)
//        case .syncSpace(let space):
//            return .spaceUpload(space: space)
//        case .addSpaces(let site, let spaces):
//            return .spacesAdd(siteId: site.id, spaces: spaces)
//        }
//    }
    
    var type: Int {
        switch self {
        case .syncSite:
            return 1
        case .syncSpace:
            return 2
        case .addSpaces:
            return 3
        case .syncGateway:
            return 4
        }
    }
    
    /// 同步site  syncSpaces:需要同时同步的spaces
    case syncSite(site: SiteData, syncSpaces: [SpaceData] = [])
    /// 同步space
    case syncSpace(space: SpaceData)
    /// 添加spaces
    case addSpaces(site: SiteData, spaces: [SpaceData])
    /// 同步网关
    case syncGateway(gateway: GatewayModel, node: Node)
    
    /// 判断操作是否相等
    static func == (lhs: SyncOperation, rhs: SyncOperation) -> Bool {
        
        guard lhs.type == rhs.type else {
            return false
        }
        
        switch (lhs, rhs) {
        case (.syncSite(let lhsSite, let lhsSyncSpaces), .syncSite(let rhsSite, let rhsSyncSpaces)):
//            if case .syncSite(let rhsSite, let rhsSyncSpaces) = rhs {
                // 后面同步的spaces包含上一个同步的所有spaces
            return lhsSite.id == rhsSite.id && (!rhsSyncSpaces.contains(where: { rhsSpace in !lhsSyncSpaces.contains(where: { $0.id == rhsSpace.id }) }) || lhsSyncSpaces.isEmpty)
//            }
        case (.syncSpace(let lhsSpace), .syncSpace(let rhsSpace)):
            return lhsSpace.siteId == rhsSpace.siteId && lhsSpace.id == rhsSpace.id
        case (.addSpaces(let lhsSite, _), .addSpaces(let rhsSite, _)):
            return lhsSite.id == rhsSite.id
        case (.syncGateway(let lhsGateway, _), .syncGateway(let rhsGateway, _)):
            return lhsGateway.mac == rhsGateway.mac
        default:
            return false
        }
    }
    
    func getNetworkApi() async -> NetowrkReqeustApi? {
        let account = UserData.currentUserId
        let region = UserData.currentServerRegion
        func isCurrent() -> Bool {
            account == UserData.currentUserId && region == UserData.currentServerRegion
                && !_Concurrency.Task<Never, Never>.isCancelled
        }
        switch self {
        case .syncSite(let site, let syncSpaces):
            guard let site = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: syncSpaces),
                  isCurrent() else { return nil }
            if site.uploadCloud {
                guard let siteData = await site.export(
                    spaceIds: syncSpaces.map({ $0.id })
                ), isCurrent() else {
                    return nil
                }
                return .siteUpload(siteData: siteData)
            }else {
                // 获取最后分配的设备地址
                let maxAddress = MeshAPI.getTheUsedDeviceAddresses(meshUUID: site.meshUUID).max()
                guard let siteData = await site.export(
                    spaceIds: syncSpaces.map({ $0.id })
                ), isCurrent() else {
                    return nil
                }
                return .siteAdd(
                    siteData: siteData,
                    useDeivceAddressNum: Int(maxAddress ?? 0)
                )
            }
        case .syncSpace(let space):
            guard await SpaceSyncCleanupCoordinator.prepare(space), isCurrent() else { return nil }
            guard let spaceData = await space.export(purpose: .cloudSync), isCurrent() else {
                return nil
            }
            return .spaceUpload(
                siteId: space.siteId,
                spaceId: space.id,
                spaceData: spaceData
            )
        case .addSpaces(let site, let spaces):
            guard let site = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: spaces),
                  isCurrent() else { return nil }
            guard let siteData = await site.export(
                spaceIds: spaces.map({ $0.id })
            ), isCurrent() else {
                return nil
            }
            return .siteUpload(siteData: siteData)
//                .spacesAdd(siteId: site.id, spaceDatas: spaceDicts)
        case .syncGateway(let gateway, let node):
            var nodeDict = await node.export()
            if nodeDict != nil {
                nodeDict = GatewayRegistrationPayloadPolicy
                    .mergeOpaqueAssociationData(
                        localNode: nodeDict ?? [:],
                        remoteNode: gateway.registrationProtectionSnapshot?.nodeData,
                        associatedAppKeyIndexes: gateway.associatedSpaces.map(
                            \.appKeyIndex
                        ),
                        isActivated: gateway.activate
                    )
                let gatewayPreconfigured: [String: Any] = gateway.export()
                nodeDict?.updateValue(gatewayPreconfigured, forKey: "gatewayPreconfigured")
            }
            return .gatewayRegister(siteId: gateway.siteId, gatewayId: gateway.mac, nodeId: node.uuid.uuidString, node: nodeDict ?? [:], updateTimestamp: gateway.lastUpdate)
        }
    }
    
}

private extension NetowrkReqeustApi {

    var configurationSpacePayloads: [[String: Any]] {
        switch self {
        case .spaceUpload(_, _, let space): return [space]
        case .siteUpload(let site), .siteAdd(let site, _): return site["spaces"] as? [[String: Any]] ?? []
        default: return []
        }
    }

    var configurationSiteTimestamp: Int64? {
        switch self {
        case .siteUpload(let site), .siteAdd(let site, _):
            return SpaceConfigurationIntegrityPolicy.integer(site["updateTimestamp"])
        default: return nil
        }
    }

    var initialSiteTimeZoneSubmission: SiteInitialTimeZoneSubmission? {
        guard case .siteAdd(let siteData, _) = self,
              let timezoneStorageValue = siteData["timezone"] as? String,
              let timezone = SiteTimeZoneValue(storageValue: timezoneStorageValue)
        else {
            return nil
        }

        let timestamp: Int64
        if let value = siteData["updateTimestamp"] as? Int64 {
            timestamp = value
        } else if let number = siteData["updateTimestamp"] as? NSNumber {
            timestamp = number.int64Value
        } else {
            return nil
        }
        return SiteInitialTimeZoneSubmission(
            timezone: timezone,
            timestamp: timestamp
        )
    }
}

#if DEBUG
extension SyncOperation {

    var diagnosticDescription: String {
        switch self {
        case .syncSite(let site, let syncSpaces):
            return "operation=syncSite siteId=\(site.id) syncSpaceCount=\(syncSpaces.count) spaces=\(Self.spacesDescription(syncSpaces))"
        case .syncSpace(let space):
            return "operation=syncSpace siteId=\(space.siteId) spaceId=\(space.id) spaceName=\(space.name)"
        case .addSpaces(let site, let spaces):
            return "operation=addSpaces siteId=\(site.id) spaceCount=\(spaces.count) spaces=\(Self.spacesDescription(spaces))"
        case .syncGateway(let gateway, _):
            return "operation=syncGateway siteId=\(gateway.siteId) gatewayId=\(gateway.mac)"
        }
    }

    private static func spacesDescription(_ spaces: [SpaceData]) -> String {
        guard !spaces.isEmpty else {
            return "[]"
        }
        return "[" + spaces.map { "spaceId=\($0.id), spaceName=\($0.name)" }.joined(separator: "; ") + "]"
    }
}
#endif

/// 同步等级
enum SyncLevel {
    /// 等待同步计时（s）
    var interval: TimeInterval {
        switch self {
        case .promptly:
            return 0
        case .normal:
            return 5
        case .slow:
            return 10
        case .custom(let interval):
            return interval
        }
    }
    
    /// 紧急
    case promptly
    /// 正常
    case normal
    /// 缓慢
    case slow
    /// 自定义
    case custom(interval: TimeInterval)
}

#if DEBUG
extension SyncLevel {

    var diagnosticDescription: String {
        switch self {
        case .promptly:
            return "promptly"
        case .normal:
            return "normal"
        case .slow:
            return "slow"
        case .custom(let interval):
            return "custom(\(interval))"
        }
    }
}
#endif

protocol CloudSynchronizationManagerDelegate: AnyObject {
    
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle)
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle)
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    ///   - error: 错误内容
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError)
    
    
    /// 取消同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步任务
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle)
    
}

extension CloudSynchronizationManagerDelegate {
    
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {}
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {}
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle) {}
    
    /// 取消同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步任务
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle) {}
    
}

/// Main-queue ownership of recovery work. A superseded task cannot release the
/// gate for its replacement when it returns from an asynchronous request.
final class PendingSynchronizationRecoveryGate {
    struct Scope: Equatable {
        let account: String
        let region: String
    }
    private var active: (token: UUID, scope: Scope)?

    func begin(scope: Scope) -> UUID? {
        guard active?.scope != scope else { return nil }
        let token = UUID()
        active = (token, scope)
        return token
    }

    func isCurrent(token: UUID) -> Bool { active?.token == token }

    func finish(token: UUID) {
        if isCurrent(token: token) { active = nil }
    }
}

class CloudSynchronizationManager {
    
    static let shared = CloudSynchronizationManager()
    
    private var syncHandles: [CloudSynchronizationHandle] = []
    
    private let mutex = DispatchQueue(label: "cloudSyncMutex")
    
    weak var delegate: CloudSynchronizationManagerDelegate?
    private var networkObservation: NSKeyValueObservation?
    private var foregroundObservation: NSObjectProtocol?
    private let recoveryGate = PendingSynchronizationRecoveryGate()

    private init() {
        networkObservation = NetworkRequest.shared.observe(\.networkable, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.resumePendingSynchronizations() }
        }
        foregroundObservation = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resumePendingSynchronizations() }
    }

    func resumePendingSynchronizations() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.resumePendingSynchronizations() }
            return
        }
        guard NetworkRequest.shared.networkable else { return }
        let scope = PendingSynchronizationRecoveryGate.Scope(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        guard let token = recoveryGate.begin(scope: scope) else { return }
        _Concurrency.Task { @MainActor in
            defer { recoveryGate.finish(token: token) }
            func isCurrent() -> Bool {
                recoveryGate.isCurrent(token: token)
                    && NetworkRequest.shared.networkable
                    && scope.account == UserData.currentUserId
                    && scope.region == String(describing: UserData.currentServerRegion)
            }
            // Hand the main queue back to UI/HTTP completions before recovery,
            // and between Sites. Task.yield alone does not guarantee this handoff.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            guard isCurrent() else { return }
            await SpaceMembershipCoordinator.resumeLeaves()
            guard isCurrent() else { return }
            SpaceConfigurationSafety.resumeLocalRemovals()
            let siteIds = SiteData.loadAll().filter { $0.state == .normal }.map(\.id)
            for siteId in siteIds {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                guard isCurrent() else { return }
                guard let site = SiteData.load(siteId: siteId), site.state == .normal else { continue }
                SiteDeviceOwnershipReconciler.reconcile(siteId: site.id)
                for space in site.spaces where !SpaceMembershipCoordinator.isLeaving(space)
                    && (try? SpaceConfigurationSafety.recoveryState(space).unbindRequested) == true {
                    _ = await SpaceConfigurationSafety.resumeUnbind(space)
                    guard isCurrent() else { return }
                }
                guard let site = SiteData.load(siteId: siteId), site.state == .normal else { continue }
                site.spaces = SpaceData.load(siteId: site.id)
                // Foreground recovery must not export every synchronized Space.
                // Full legacy inspection still runs on Space entry and explicit sync.
                let preparedSite = await SpaceSyncCleanupCoordinator.prepareBatch(
                    site: site, spaces: site.spaces, requiringSuccessfulPreparation: false, shouldContinue: isCurrent,
                    shouldPrepare: { space in
                        self.getSpaceCurrentSyncState(space) == nil
                            && (space.needUploadCloud || SpaceConfigurationSafety.hasPendingUpload(space)
                                || SpaceConfigurationSafety.isBlocked(space))
                    }
                )
                guard isCurrent() else { return }
                guard let site = preparedSite else { continue }
                if (try? SiteTriggerZoneStore.load(site).pending) != nil, site.canManageSiteTriggerZones {
                    _ = await SiteTriggerZoneCoordinator(site: site).synchronize()
                    guard isCurrent() else { return }
                }
                // Remote Zone reconciliation can also update local Space state.
                guard let site = SiteData.load(siteId: siteId), site.state == .normal else { continue }
                site.spaces = SpaceData.load(siteId: site.id)
                let spaces = site.spaces.filter { space in
                    SpaceConfigurationSafety.canAutomaticallyUpload(space)
                        && (space.needUploadCloud || SpaceConfigurationSafety.hasPendingUpload(space))
                        && (!SpaceConfigurationSafety.isBlocked(space) || SpaceConfigurationSafety.hasPendingUpload(space))
                        && getSpaceCurrentSyncState(space) == nil
                }
                guard !spaces.isEmpty else { continue }
                addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: spaces), level: .promptly)
            }
        }
    }
    
    /// 添加同步云端数据操作
    /// - Parameters:
    ///   - operation: 操作数据类型
    ///   - level: 同步等级
    @discardableResult
    func addSynchronizationHandle(
        operation: SyncOperation,
        level: SyncLevel,
        result stateCallback: ((CloudSynchronizationState) -> Void)? = nil
    ) -> CloudSynchronizationHandle {
        
        var addOperation = operation
        // 发现同一个同步操作
        if let lastHandleIndex = syncHandles.firstIndex(where: { $0.operation == operation }) {
            let lastHandle = syncHandles[lastHandleIndex]
            // 判断同一个site添加space则合并添加的spaces
            if case .addSpaces(let site, let spaces) = operation {
                if case .addSpaces(let oldSite, let oldSpaces) = lastHandle.operation, site.id == oldSite.id {
                    // 判断正在队列的添加spaces操作和最新的添加spaces数据是否需要合并
                    var appendSpaces = oldSpaces.filter({ oldSpace in !spaces.contains(where: { $0.id == oldSpace.id }) })
                    if appendSpaces.count > 0 {
                        appendSpaces.append(contentsOf: spaces)
                        addOperation = .addSpaces(site: site, spaces: appendSpaces)
                    }
                }
            }
            // 取消上一个同步操作
            lastHandle.cancel()
//            DispatchQueue.global().async {
            self.mutex.sync {
               _ = self.syncHandles.remove(at: lastHandleIndex)
            }
//            }
        }
        
        let handle = CloudSynchronizationHandle(operation: addOperation, level: level, result: {[weak self] (resultHandle, state) in
            guard let self = self else { return }
            stateCallback?(state)
            switch state {
            case .wait:
                break
            case .inProgress:
                self.delegate?.cloudSyncManager(self, didStartSync: resultHandle)
            case .successful:
                self.delegate?.cloudSyncManager(self, didSyncFinished: resultHandle)
                self.mutex.sync {
                    self.syncHandles.removeAll(where: { $0 == resultHandle })
                }
            case .failure(let error):
                self.delegate?.cloudSyncManager(self, didSyncFailure: resultHandle, error: error)
                self.mutex.sync {
                    self.syncHandles.removeAll(where: { $0 == resultHandle })
                }
            case .cancel:
                self.delegate?.cloudSyncManager(self, cancelSyncHandle: resultHandle)
                self.mutex.sync {
                    self.syncHandles.removeAll(where: { $0 == resultHandle })
                }
            }
        })
//        DispatchQueue.global().async {
            self.mutex.sync {
                self.syncHandles.append(handle)
            }
//        }
        
        
        handle.start()
        return handle
    }
    
    /// 取消同步操作
    @discardableResult
    func cancelSynchronizationHandle(operation: SyncOperation) -> Bool {
        
        if let lastHandleIndex = syncHandles.firstIndex(where: { $0.operation == operation }) {
            syncHandles[lastHandleIndex].cancel()
            self.mutex.sync {
               _ = syncHandles.remove(at: lastHandleIndex)
            }
            return true
        }
        return false
    }
    
    /// 取消site相关的同步操作
    func cancelSynchronizationHandle(site: SiteData) {
        
        // 获取site相关同步操作
        let handles = syncHandles.filter({ handle in
            switch handle.operation {
            case .syncSite(let syncSite, _):
                return syncSite.id == site.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let syncSite, _):
                return syncSite.id == site.id
            case .syncGateway(let gateway, _):
                return gateway.siteId == site.id
            }
        })
        handles.forEach { handle in
            handle.cancel()
            if let index = syncHandles.firstIndex(of: handle) {
                self.mutex.sync {
                    _ = syncHandles.remove(at: index)
                }
            }
        }
    }
    
    /// Keep unrelated peers queued when a batch containing the leaving Space is cancelled.
    func suspendForMembershipLeave(space: SpaceData) {
        var remaining: [SyncOperation] = []
        for handle in syncHandles {
            switch handle.operation {
            case .syncSite(let site, let spaces), .addSpaces(let site, let spaces):
                if spaces.contains(where: { $0.siteId == space.siteId && $0.id == space.id }) {
                    let peers = spaces.filter { $0.id != space.id && !SpaceMembershipCoordinator.isLeaving($0) }
                    if !peers.isEmpty { remaining.append(.syncSite(site: site, syncSpaces: peers)) }
                }
            default: break
            }
        }
        cancelSynchronizationHandle(space: space)
        for operation in remaining { addSynchronizationHandle(operation: operation, level: .normal) }
    }

    /// 取消space相关的同步操作
    func cancelSynchronizationHandle(space: SpaceData) {
        
        // 获取space相关同步操作
        let handles = syncHandles.filter({ handle in
            switch handle.operation {
            case .syncSite(_, let syncSpaces):
                return syncSpaces.contains(where: { $0.siteId == space.siteId && $0.id == space.id })
            case .syncSpace(let syncSpace):
                return space.siteId == syncSpace.siteId && space.id == syncSpace.id
            case .addSpaces(_, let spaces):
                return spaces.contains(where: { $0.siteId == space.siteId && $0.id == space.id })
            default:
                return false
            }
        })
        for handle in handles {
            handle.cancel()
            if let index = syncHandles.firstIndex(of: handle) {
                self.mutex.sync {
                    _ = syncHandles.remove(at: index)
                }
            }
        }
    }
    
    
    /// 修改同步操作同步等级（仅限等待中的操作）
    /// - Parameters:
    ///   - handle: 同步操作
    ///   - level: 等级
    func setSynchronizationHandleLevel(handle: CloudSynchronizationHandle, level: SyncLevel) {
        handle.level = level
        handle.cancel()
        // 重新开始
        handle.start()
    }
    
    /// 根据sites数据获取当前同步状态
    /// - Returns: 当前同步操作(所有site)
    func getSitesCurrentSyncState() -> CloudSynchronizationState? {
        
        // 获取site相关同步操作
        let siteHandles = syncHandles.filter({ handle in
            if case .syncSite = handle.operation {
                return true
            }
            return false
        })
        
        var state: CloudSynchronizationState?
        // 进行中
        if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationState.inProgress.rawValue }) {
            state = .inProgress
        }else if let failedHandle = siteHandles.first(where: { // 操作全部完成并存在失败
            if case .failure = $0.state { return true }
            return false
        }) {
            state = failedHandle.state
        }else if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationState.successful.rawValue }) { // 操作全部完成并全部成功
            state = .successful
        }else if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationState.wait.rawValue }) { // 操作全部都在等待
            state = .wait
        }
        return state
    }
    
    /// 根据site数据获取当前同步操作
    /// - Parameter site: site
    /// - Returns: 当前同步操作
    func getSiteCurrentSyncHandle(_ site: SiteData) -> CloudSynchronizationHandle? {
        
        // 获取site/space相关同步操作
        let handle = syncHandles.first(where: { handle in
            switch handle.operation {
            case .syncSite(let syncSite, _):
                return syncSite.id == site.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let syncSite, _):
                return syncSite.id == site.id
            case .syncGateway(let gateway, _):
                return site.id == gateway.siteId
            }
        })
        return handle
    }
    
    /// 根据site数据获取当前同步状态（复合状态可能包含下级多个space状态）
    /// - Parameter site: site
    /// - Returns: 当前同步操作
    func getSiteCurrentSyncState(_ site: SiteData) -> CloudSynchronizationState? {
        
        // 获取site/space相关同步操作
        let handles = syncHandles.filter({ handle in
            switch handle.operation {
            case .syncSite(let syncSite, _):
                return site.id == syncSite.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let syncSite, _):
                return site.id == syncSite.id
            case .syncGateway(let gateway, _):
                return site.id == gateway.siteId
            }
        })
        
        var state: CloudSynchronizationState?
        // 进行中
        if handles.contains(where: { $0.state.rawValue == CloudSynchronizationState.inProgress.rawValue }) {
            state = .inProgress
        }else if let failedHandle = handles.first(where: { // 操作全部完成并存在失败
            if case .failure = $0.state { return true }
            return false
        }) {
            state = failedHandle.state
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationState.successful.rawValue }) { // 操作全部完成并全部成功
            state = .successful
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationState.wait.rawValue }) { // 操作全部都在等待
            state = .wait
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationState.cancel.rawValue }) { // 取消
            state = .cancel
        }
        return state
    }
    
    
    /// 根据space数据获取当前同步状态
    /// - Parameter space: space
    /// - Returns: 当前同步操作
    func getSpaceCurrentSyncState(_ space: SpaceData) -> CloudSynchronizationHandle? {
        
        let handle = syncHandles.first(where: { handle in
            switch handle.operation {
            case .syncSite(_, let syncSpaces):
                return syncSpaces.contains(where: { $0.id == space.id })
            case .syncSpace(let syncSpace):
                return space.id == syncSpace.id
            case .addSpaces(_, let spaces):
                return spaces.contains(where: { $0.id == space.id })
            default:
                return false
            }
        })
        return handle
    }
    
    /// 根据gateway数据获取当前同步状态
    /// - Parameter gateway: gateway
    /// - Returns: 当前同步操作
    func getGatewayCurrentSyncState(_ gateway: GatewayModel) -> CloudSynchronizationHandle? {
        
        let handle = syncHandles.first(where: { handle in
            switch handle.operation {
            case .syncGateway(let syncGateway, _):
                return gateway.mac == syncGateway.mac
            default:
                return false
            }
        })
        return handle
    }
    
}

/// 云端同步状态
enum CloudSynchronizationState {
    
    var rawValue: Int {
        switch self {
        case .wait:
            return 0
        case .inProgress:
            return 1
        case .successful:
            return 2
        case .failure:
            return 3
        case .cancel:
            return 4
        }
    }
    /// 等待
    case wait
    /// 进行中
    case inProgress
    /// 成功
    case successful
    /// 失败
    case failure(error: NetworkApiError)
    /// 已取消
    case cancel
}

class CloudSynchronizationHandle: NSObject {
    
    /// 同步操作回调   state：状态
    typealias SyncHandleCallback = ((CloudSynchronizationHandle, CloudSynchronizationState)->Void)
    
    typealias AsyncTask = _Concurrency.Task
    
    /// 操作类型
    let operation: SyncOperation
    /// 等级
    var level: SyncLevel {
        didSet {
            guard case .wait = state else {
                return
            }
            startTimewait()
        }
    }
    /// 状态
    var state: CloudSynchronizationState = .wait
    /// 等待定时器
//    private var waitTimer: Timer?
    /// 网络请求操作
    private var requestHandle: Cancellable?
    /// Gateway Register 使用共享 Authorization 服务执行。
    private var gatewayAuthorizationTask: _Concurrency.Task<Void, Never>?
    private var configurationUploadTask: _Concurrency.Task<Void, Never>?
    /// 同步数据操作回调
    private var handleCallback: SyncHandleCallback?
    
    private var waitTimer: DispatchSourceTimer?
    // 异步队列
    private let asyncQueue = DispatchQueue(label: "com.example.asyncQueue", attributes: .concurrent)
    
    /// 初始化数据同步云端操作
    /// - Parameters:
    ///   - operation: 操作类型
    ///   - level: 等级
    ///   - callback: 状态回调
    init(operation: SyncOperation, level: SyncLevel, result: SyncHandleCallback?) {
        self.operation = operation
        self.level = level
        self.handleCallback = result
    }
    
    deinit {
//        print("deinit \(operation)")
    }
    
    /// 开始
    func start() {
//        state = .wait
//        state = .inProgress
//        handleCallback?(self, state)
        // 判断是否有网络
        guard NetworkRequest.shared.networkable else {
            let error: NetworkApiError = .noNetwork
            state = .failure(error: error)
            // 更新缓存
            switch self.operation {
            case .syncSite(let site, let spaces):
                site.syncCloudError = error
                spaces.forEach({ 
                    $0.syncCloudError = error
                    $0.save()
                })
                site.save()
            case .addSpaces(_, let spaces):
                spaces.forEach({
                    $0.syncCloudError = error
                    $0.save()
                })
            case .syncSpace(let space):
                space.syncCloudError = error
                space.save()
            case .syncGateway(let gateway, _):
                gateway.syncCloudError = error
                gateway.save()
            }
            DispatchQueue.main.async {
                self.handleCallback?(self, self.state)
            }
            return
        }
        configurationSpaces.forEach { $0.syncCloudError = nil }
        startTimewait()
    }
    
    /// 取消
    func cancel() {
        stopTimewait()
        requestHandle?.cancel()
        gatewayAuthorizationTask?.cancel()
        gatewayAuthorizationTask = nil
        configurationUploadTask?.cancel()
        configurationUploadTask = nil
        state = .cancel
        DispatchQueue.main.async {
            self.handleCallback?(self, self.state)
        }
    }
    
    /// 进入计时
    private func startTimewait() {
        if waitTimer != nil {
            stopTimewait()
        }
        // 创建定时器
        let timer = DispatchSource.makeTimerSource(queue: asyncQueue)
        timer.schedule(deadline: .now() + level.interval, repeating: .infinity)
        timer.setEventHandler { [weak self] in
            self?.syncOperation()
        }
        timer.resume()
        self.waitTimer = timer
    }
    
    /// 停止计时
    private func stopTimewait() {
        waitTimer?.cancel()
        waitTimer = nil
    }

    private func finishExportFailure() {
        let error = configurationSpaces.compactMap { $0.syncCloudError }.first ?? .configurationUnavailable
        finishConfigurationFailure(error)
    }

    private func finishConfigurationFailure(_ error: NetworkApiError) {
        state = .failure(error: error)
        switch operation {
        case .syncSite(let site, let spaces):
            site.syncCloudError = error
            site.save()
            spaces.forEach {
                $0.syncCloudError = error
                $0.save()
            }
        case .addSpaces(_, let spaces):
            spaces.forEach {
                $0.syncCloudError = error
                $0.save()
            }
        case .syncSpace(let space):
            space.syncCloudError = error
            space.save()
        case .syncGateway(let gateway, _):
            gateway.syncCloudError = error
            gateway.save()
        }
        DispatchQueue.main.async {
            self.handleCallback?(self, self.state)
        }
    }

    private func finishInvalidatedConfiguration() {
        state = .cancel
        handleCallback?(self, state)
    }
    
    private var configurationSpaces: [SpaceData] {
        switch operation {
        case .syncSpace(let space): return [space]
        case .syncSite(_, let spaces), .addSpaces(_, let spaces): return spaces
        case .syncGateway: return []
        }
    }

    /// Persist only the Site version actually accepted by this request.
    @MainActor
    private func confirmSiteUpload(api: NetowrkReqeustApi, response: [String: Any]) -> Bool {
        let site: SiteData
        switch operation {
        case .syncSite(let value, _), .addSpaces(let value, _): site = value
        default: return true
        }
        guard let submitted = api.configurationSiteTimestamp else { return false }
        let previousTimestamp = site.lastUploadCloudTimestamp
        let previousMask = site.pendingSitePropsMask
        let previousPendingTimestamp = site.pendingSitePropsTimestamp
        let previousError = site.syncCloudError
        if case .siteAdd = api, let resources = JSON(response)["data"]["addrLists"].dictionaryObject {
            site.setOwnerProvisioner(addressData: resources)
        }
        if let initialSubmission = api.initialSiteTimeZoneSubmission {
            let current = SitePropsLocalState(
                values: SitePropsValues(siteName: site.name, imageId: site.imageId,
                    timezone: site.timezone.flatMap(SiteTimeZoneValue.init(storageValue:))),
                lastUpdate: site.lastUpdate,
                lastUploadCloudTimestamp: previousTimestamp,
                pending: SitePropsPendingState(fields: previousMask, timestamp: previousPendingTimestamp)
            )
            let reconciled = SitePropsEditPolicy.localStateAfterSuccessfulInitialSiteUpload(
                current: current, submission: initialSubmission)
            site.lastUploadCloudTimestamp = reconciled.lastUploadCloudTimestamp
            site.pendingSitePropsMask = reconciled.pending.fields
            site.pendingSitePropsTimestamp = reconciled.pending.timestamp
        } else {
            site.lastUploadCloudTimestamp = SpaceConfigurationIntegrityPolicy.confirmedTimestamp(
                previous: previousTimestamp, submitted: submitted)
        }
        site.syncCloudError = nil
        guard site.save() else {
            site.lastUploadCloudTimestamp = previousTimestamp
            site.pendingSitePropsMask = previousMask
            site.pendingSitePropsTimestamp = previousPendingTimestamp
            site.syncCloudError = previousError
            return false
        }
        return true
    }

    /// 开始同步到服务器
    func syncOperation() {
        if waitTimer != nil {
            stopTimewait()
        }
        if case .syncGateway(let gateway, _) = operation,
           (gateway.isServerDeletionInProgress ||
            gateway.serverDeletionPendingLocalReset) {
            state = .cancel
            DispatchQueue.main.async {
                self.handleCallback?(self, self.state)
            }
            return
        }
        state = .inProgress
        DispatchQueue.main.async {
            self.handleCallback?(self, self.state)
        }
//        print(operation)
        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {[weak self] in
//            guard let self = self else { return }
//            self.state = arc4random_uniform(2) == 1 ? .successful : .failure(error: .noNetwork)
//            self.handleCallback?(self, self.state)
//        }
        requestHandle?.cancel()
        if case .syncGateway(let gateway, let node) = operation {
            gatewayAuthorizationTask?.cancel()
            gatewayAuthorizationTask = AsyncTask { @MainActor [weak self] in
                guard let self, !_Concurrency.Task<Never, Never>.isCancelled else { return }
                while !_Concurrency.Task<Never, Never>.isCancelled {
                    let requestedGeneration = gateway.lastUpdate
                    let result = await GatewayServerAuthorizationService.shared.authorizeWithReceipt(
                        gateway: gateway,
                        node: node,
                        policy: .always,
                        requestedGeneration: requestedGeneration
                    )
                    guard !_Concurrency.Task<Never, Never>.isCancelled else { return }

                    switch result {
                    case .success(let receipt):
                        gateway.lastUploadCloudTimestamp =
                            GatewayCloudSyncGenerationPolicy.confirmed(
                                previous: gateway.lastUploadCloudTimestamp,
                                submitted: receipt.submittedGeneration
                            )
                        gateway.syncCloudError = nil
                        gateway.save()
                        if GatewayCloudSyncGenerationPolicy.needsAnotherUpload(
                            current: gateway.lastUpdate,
                            confirmed: gateway.lastUploadCloudTimestamp
                        ) {
                            continue
                        }
                        self.state = .successful
                    case .failure(let authorizationError):
                        self.state = .failure(error: authorizationError.networkApiError)
                        gateway.syncCloudError = authorizationError.networkApiError
                        gateway.save()
                    }
                    break
                }
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                self.gatewayAuthorizationTask = nil
                self.handleCallback?(self, self.state)
            }
            return
        }
        configurationUploadTask?.cancel()
        configurationUploadTask = AsyncTask { @MainActor in
            let account = UserData.currentUserId
            let region = UserData.currentServerRegion
            let lifecycle = Dictionary(self.configurationSpaces.compactMap { space -> (String, SpaceRecoveryState)? in
                guard let context = try? SpaceConfigurationSafety.recoveryState(space) else { return nil }
                return (space.id, context)
            }, uniquingKeysWith: { first, _ in first })
            func isCurrentOperation() -> Bool {
                account == UserData.currentUserId && region == UserData.currentServerRegion && self.configurationSpaces.allSatisfy { space in
                    lifecycle[space.id].map { SpaceConfigurationSafety.isCurrent($0, space: space) } == true
                }
            }
            guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
            let hadPending = self.configurationSpaces.contains { SpaceConfigurationSafety.hasPendingUpload($0) }
            if case .syncSite(let site, _) = self.operation, !site.uploadCloud,
               let createdTimestamp = lifecycle.values.compactMap(\.siteCreationTimestamp).max() {
                // Recover acceptance/resources after a crash before Site.save().
                let result = await NetworkRequest.shared.request(.siteInfo(siteId: site.id))
                guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrentOperation() else { return }
                guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
                      remote["uuid"] as? String == site.id,
                      let provisioner = remote["provisioner"] as? [String: Any] else {
                    self.finishConfigurationFailure(SpaceConfigurationSafety.uploadUnconfirmed)
                    return
                }
                site.setProvisioner(provisionerData: provisioner)
                site.lastUploadCloudTimestamp = createdTimestamp
                guard site.save() else { self.finishConfigurationFailure(SpaceConfigurationSafety.uploadUnconfirmed); return }
            }
            for space in self.configurationSpaces {
                if case .failure(let error) = await SpaceConfigurationSafety.resumeUpload(space) {
                    guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                    guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
                    self.finishConfigurationFailure(error)
                    return
                }
            }
            guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
            if hadPending && !self.configurationSpaces.contains(where: { $0.needUploadCloud }) {
                let sitePending: Bool
                switch self.operation {
                case .syncSite(let site, _), .addSpaces(let site, _): sitePending = site.needUploadCloud
                default: sitePending = false
                }
                if !sitePending {
                    self.state = .successful
                    self.handleCallback?(self, self.state)
                    return
                }
            }
            guard let api = await self.operation.getNetworkApi() else {
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
                self.finishExportFailure()
                return
            }
            #if DEBUG
            print("""
            [CloudSync][Request]
            \(self.operation.diagnosticDescription)
            apiTarget=\(api.diagnosticName)
            apiPath=\(api.path)
            level=\(self.level.diagnosticDescription)
            """)
            #endif
            guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
            guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
            let submissions = api.configurationSpacePayloads
            let creationTimestamp: Int64?
            if case .siteAdd = api { creationTimestamp = api.configurationSiteTimestamp } else { creationTimestamp = nil }
            var contexts: [String: SpaceRecoveryState] = [:]
            for payload in submissions {
                guard let id = payload["uuid"] as? String,
                      let space = self.configurationSpaces.first(where: { $0.id == id }),
                      let context = SpaceConfigurationSafety.prepareSubmission(space, payload: payload, siteCreationTimestamp: creationTimestamp) else {
                    for space in self.configurationSpaces {
                        if let context = contexts[space.id] { SpaceConfigurationSafety.discardUnsentSubmission(context, space: space) }
                    }
                    self.finishConfigurationFailure(SpaceConfigurationSafety.uploadUnconfirmed)
                    return
                }
                contexts[id] = context
            }
            let requestResult = await NetworkRequest.shared.request(api)
            var result = requestResult
            guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
            var confirmedConfigurationIds = Set<String>()
            switch result {
            case .success:
                for space in self.configurationSpaces {
                    if let context = contexts[space.id], !SpaceConfigurationSafety.markSubmissionAccepted(context, space: space) {
                        result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
                    }
                }
            case .failure(let error):
                for space in self.configurationSpaces {
                    if let context = contexts[space.id] {
                        SpaceConfigurationSafety.rejectSubmission(context, space: space, error: error)
                    }
                }
            }
            // Confirm the Site independently of per-Space local persistence.
            // First creation must retain its assigned resources even if a Space save fails.
            if case .success(let response) = requestResult,
               !self.confirmSiteUpload(api: api, response: response) {
                result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
            }
            guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
            if case .success = requestResult {
                for payload in submissions {
                    guard let id = payload["uuid"] as? String,
                          let space = self.configurationSpaces.first(where: { $0.id == id }),
                          let context = contexts[id] else {
                        result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
                        continue
                    }
                    if SpaceConfigurationSafety.finishAcceptedSubmission(context, space: space) {
                        confirmedConfigurationIds.insert(id)
                    } else {
                        result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
                    }
                }
            }
            let completionResult = result
            let completedConfigurationIds = confirmedConfigurationIds
            await MainActor.run {
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
                switch completionResult {
                case .success:
                    #if DEBUG
                    print("""
                    [CloudSync][Success]
                    \(self.operation.diagnosticDescription)
                    apiTarget=\(api.diagnosticName)
                    apiPath=\(api.path)
                    """)
                    #endif
                    self.state = .successful

                case .failure(let error):
                    #if DEBUG
                    print("""
                    [CloudSync][Failure]
                    \(self.operation.diagnosticDescription)
                    apiTarget=\(api.diagnosticName)
                    apiPath=\(api.path)
                    errorCode=\(error.code)
                    error=\(error.diagnosticDescription)
                    """)
                    #endif
                    self.state = .failure(error: error)
                    // 更新缓存
                    switch self.operation {
                    case .syncSite(let site, let syncSpaces):
                        site.syncCloudError = error
                        site.save()
                        syncSpaces.filter { !completedConfigurationIds.contains($0.id) }.forEach({
                            $0.syncCloudError = error
                            $0.save()
                        })
                    case .addSpaces(_, let spaces):
                        spaces.filter { !completedConfigurationIds.contains($0.id) }.forEach({
                            $0.syncCloudError = error
                            $0.save()
                        })
//                        site.save()
                    case .syncSpace(let space):
                        space.syncCloudError = error
                        space.save()
                    case .syncGateway(let gateway, _):
                        gateway.syncCloudError = error
                        gateway.save()
                    }
                    
                    
                }
                self.handleCallback?(self, self.state)
            }
        }
    }
    
}
