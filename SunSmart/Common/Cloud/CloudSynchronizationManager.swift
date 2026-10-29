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
    
    func includesConfiguration(of space: SpaceData) -> Bool {
        switch self {
        case .syncSpace(let target):
            return target.siteId == space.siteId && target.id == space.id
        case .syncSite(let site, let spaces), .addSpaces(let site, let spaces):
            return site.id == space.siteId && spaces.contains { $0.siteId == space.siteId && $0.id == space.id }
        case .syncGateway: return false
        }
    }

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
    var isActive: Bool { active != nil }

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

/// An in-memory scheduling boundary, never a recovery/submission record.
/// A fresh launch therefore resumes durable dirty data through the ordinary recovery path.
struct DeviceAddCloudScope {
    let account = UserData.currentUserId
    let region = String(describing: UserData.currentServerRegion)
    let siteId: String
    let spaceId: String
    let meshUUID: String
    let networkId: String

    init(space: SpaceData) {
        siteId = space.siteId; spaceId = space.id
        meshUUID = space.meshUUID; networkId = space.meshNetworkId
    }

    var currentSpace: SpaceData? {
        guard account == UserData.currentUserId,
              region == String(describing: UserData.currentServerRegion),
              let space = SpaceData.load(siteId: siteId, spaceId: spaceId).first,
              space.meshUUID == meshUUID, space.meshNetworkId == networkId else { return nil }
        return space
    }

    func contains(_ operation: SyncOperation) -> Bool {
        switch operation {
        case .syncSite(let site, _), .addSpaces(let site, _):
            return site.id == siteId && site.meshUUID == meshUUID
        case .syncSpace(let space):
            return space.siteId == siteId && space.id == spaceId
                && space.meshUUID == meshUUID && space.meshNetworkId == networkId
        case .syncGateway: return false
        }
    }
}

private final class DeviceAddCloudAdmission {
    let scope: DeviceAddCloudScope
    var ready: ((Bool) -> Void)?
    var preparing = false
    init(scope: DeviceAddCloudScope, ready: @escaping (Bool) -> Void) {
        self.scope = scope; self.ready = ready
    }
}

private extension SyncOperation {
    var configurationSiteMeshUUID: String? {
        switch self {
        case .syncSite(let site, _), .addSpaces(let site, _): return site.meshUUID
        case .syncSpace(let space): return space.meshUUID
        case .syncGateway: return nil
        }
    }
    var configurationSiteId: String? {
        switch self {
        case .syncSite(let site, _), .addSpaces(let site, _): return site.id
        case .syncSpace(let space): return space.siteId
        case .syncGateway: return nil
        }
    }
    var spacesForDeviceAdd: [SpaceData] {
        switch self {
        case .syncSite(_, let spaces), .addSpaces(_, let spaces): return spaces
        case .syncSpace(let space): return [space]
        case .syncGateway: return []
        }
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
    private var deviceAddAdmissions: [UUID: DeviceAddCloudAdmission] = [:]

    func beginDeviceAdd(scope: DeviceAddCloudScope, ready: @escaping (Bool) -> Void) -> UUID {
        precondition(Thread.isMainThread)
        let token = UUID()
        deviceAddAdmissions[token] = DeviceAddCloudAdmission(scope: scope, ready: ready)
        for handle in syncHandles where handle.state.rawValue == CloudSynchronizationState.wait.rawValue
            && !handle.isDeviceAddAdmission && handle.isCurrentDeviceAddContext && scope.contains(handle.operation) {
            handle.deferForDeviceAdd()
        }
        coalesceDeviceAddWaits(siteId: scope.siteId)
        DispatchQueue.main.async { self.drainDeviceAddSynchronizations() }
        return token
    }

    func endDeviceAdd(token: UUID) {
        precondition(Thread.isMainThread)
        deviceAddAdmissions.removeValue(forKey: token)
        drainDeviceAddSynchronizations()
    }

    func isAddingDevices(to space: SpaceData) -> Bool {
        deviceAddAdmissions.values.contains { $0.scope.currentSpace != nil && $0.scope.contains(.syncSpace(space: space)) }
    }

    private func shouldDeferForDeviceAdd(_ operation: SyncOperation, excluding handle: CloudSynchronizationHandle? = nil) -> Bool {
        if deviceAddAdmissions.values.contains(where: { $0.scope.currentSpace != nil && $0.scope.contains(operation) }) { return true }
        // An already sent final upload is allowed to settle. Later edits form another generation.
        return syncHandles.contains { other in
            other !== handle && !other.isCoalesced && other.isCurrentDeviceAddContext
                && ((other.serializesDeviceAdd && other.state.rawValue <= CloudSynchronizationState.inProgress.rawValue)
                    || (handle?.serializesDeviceAdd == true && other.state.rawValue == CloudSynchronizationState.inProgress.rawValue))
                && other.operation.configurationSiteId == operation.configurationSiteId
                && operation.configurationSiteId != nil
        }
    }

    private func coalesceDeviceAddWaits(siteId: String) {
        let handles = syncHandles.filter { $0.isDeferredForDeviceAdd && !$0.isCoalesced
            && $0.state.rawValue == CloudSynchronizationState.wait.rawValue
            && $0.isCurrentDeviceAddContext && $0.operation.configurationSiteId == siteId }
        guard let first = handles.first, let site = SiteData.load(siteId: siteId) else { return }
        var spaces = first.operation.spacesForDeviceAdd
        for handle in handles.dropFirst() {
            for space in handle.operation.spacesForDeviceAdd where !spaces.contains(where: { $0.id == space.id }) { spaces.append(space) }
            handle.isCoalesced = true
            first.appendCallback { [handle] _, state in handle.receiveCoalescedState(state) }
        }
        first.operation = .syncSite(site: site, syncSpaces: spaces)
    }

    private func drainDeviceAddSynchronizations() {
        precondition(Thread.isMainThread)
        for (token, admission) in deviceAddAdmissions where admission.ready != nil && !admission.preparing {
            guard !recoveryGate.isActive,
                  !syncHandles.contains(where: { $0.isCurrentDeviceAddContext && admission.scope.contains($0.operation)
                      && ($0.state.rawValue == CloudSynchronizationState.inProgress.rawValue
                          || ($0.isDeviceAddAdmission && $0.state.rawValue == CloudSynchronizationState.wait.rawValue)) }) else { continue }
            admission.preparing = true
            _Concurrency.Task { @MainActor in
                var allowed = admission.scope.currentSpace != nil
                if let space = admission.scope.currentSpace, SpaceConfigurationSafety.hasPendingUpload(space) {
                    // Reuse the entire recovery flow, including first-Site acceptance
                    // and assigned address resources, before provisioning mutates it.
                    if let site = SiteData.load(siteId: space.siteId) {
                        allowed = await withCheckedContinuation { continuation in
                            var completed = false
                            self.enqueueSynchronization(operation: .syncSite(site: site, syncSpaces: [space]), level: .promptly,
                                result: { state in
                                    guard !completed, state.rawValue >= CloudSynchronizationState.successful.rawValue else { return }
                                    completed = true
                                    continuation.resume(returning: state.rawValue == CloudSynchronizationState.successful.rawValue)
                                }, isDeviceAddAdmission: true)
                        }
                    } else { allowed = false }
                }
                guard self.deviceAddAdmissions[token] === admission else { return }
                if let space = admission.scope.currentSpace {
                    allowed = allowed && space.canEditing && SpaceMembershipCoordinator.allowsConfiguration(space)
                        && !SpaceConfigurationSafety.isBlocked(space)
                } else { allowed = false }
                let ready = admission.ready; admission.ready = nil
                ready?(allowed)
            }
        }
        for handle in syncHandles where handle.isDeferredForDeviceAdd && !handle.isCoalesced {
            guard case .wait = handle.state else { continue }
            guard !shouldDeferForDeviceAdd(handle.operation, excluding: handle) else { continue }
            guard handle.isCurrentDeviceAddContext, handle.reloadDeviceAddSnapshot() else { handle.cancel(); continue }
            handle.level = .promptly
            handle.isDeferredForDeviceAdd = false
            handle.start()
        }
    }

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
            defer { recoveryGate.finish(token: token); drainDeviceAddSynchronizations() }
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
                        !self.isAddingDevices(to: space) && self.getSpaceCurrentSyncState(space) == nil
                            && !SpaceConfigurationSafety.hasPendingUpload(space)
                            && (space.needUploadCloud || SpaceConfigurationSafety.isBlocked(space))
                    }
                )
                guard isCurrent() else { return }
                guard let site = preparedSite else { continue }
                if (try? SiteExtensionStore.load(site).pending) != nil, site.canManageSiteTriggerZones {
                    _ = await SiteTriggerZoneCoordinator(site: site).synchronize()
                    guard isCurrent() else { return }
                }
                // Remote Zone reconciliation can also update local Space state.
                guard let site = SiteData.load(siteId: siteId), site.state == .normal else { continue }
                site.spaces = SpaceData.load(siteId: site.id)
                let spaces = site.spaces.filter { space in
                    !isAddingDevices(to: space) && (SpaceConfigurationSafety.canAutomaticallyUpload(space)
                        || SpaceConfigurationSafety.canResumePendingUpload(space))
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
        enqueueSynchronization(operation: operation, level: level, result: stateCallback)
    }

    @discardableResult
    private func enqueueSynchronization(operation: SyncOperation, level: SyncLevel,
        result stateCallback: ((CloudSynchronizationState) -> Void)?, isDeviceAddAdmission: Bool = false) -> CloudSynchronizationHandle {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { self.enqueueSynchronization(operation: operation, level: level,
                result: stateCallback, isDeviceAddAdmission: isDeviceAddAdmission) }
        }
        // Keep a single waiting handle and every caller's completion during a batch.
        let deferred = !isDeviceAddAdmission && shouldDeferForDeviceAdd(operation)
        if deferred, let pending = syncHandles.first(where: { $0.serializesDeviceAdd && !$0.isCoalesced && !$0.isDeviceAddAdmission
            && $0.state.rawValue == CloudSynchronizationState.wait.rawValue
            && $0.isCurrentDeviceAddContext && $0.operation.configurationSiteId == operation.configurationSiteId }),
           let siteId = operation.configurationSiteId, let site = SiteData.load(siteId: siteId) {
            var spaces = pending.operation.spacesForDeviceAdd
            for space in operation.spacesForDeviceAdd {
                if let index = spaces.firstIndex(where: { $0.id == space.id }) { spaces[index] = space }
                else { spaces.append(space) }
            }
            pending.operation = .syncSite(site: site, syncSpaces: spaces)
            if let stateCallback { pending.appendCallback { _, state in stateCallback(state) } }
            return pending
        }
        var addOperation = operation
        // 发现同一个同步操作
        if !deferred && !isDeviceAddAdmission, let lastHandleIndex = syncHandles.firstIndex(where: { $0.operation == operation && !$0.isCoalesced }) {
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
            if state.rawValue >= CloudSynchronizationState.successful.rawValue {
                DispatchQueue.main.async { self.drainDeviceAddSynchronizations() }
            }
        })
        handle.isDeviceAddAdmission = isDeviceAddAdmission
        if isDeviceAddAdmission { handle.serializesDeviceAdd = true }
        handle.mayStart = { [weak self, weak handle] in
            guard let self, let handle else { return false }
            if handle.isDeviceAddAdmission { return true }
            if self.shouldDeferForDeviceAdd(handle.operation, excluding: handle) {
                handle.deferForDeviceAdd()
                return false
            }
            return true
        }
        if deferred { handle.deferForDeviceAdd() }
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
        guard case .wait = handle.state else { return }
        handle.level = level
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
        
        let handle = syncHandles.first { $0.operation.includesConfiguration(of: space) }
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
    fileprivate(set) var operation: SyncOperation
    fileprivate var mayStart: (() -> Bool)?
    fileprivate var isDeferredForDeviceAdd = false
    fileprivate var isCoalesced = false
    fileprivate var serializesDeviceAdd = false
    fileprivate var isDeviceAddAdmission = false
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let siteMeshUUID: String?
    private var deviceAddScopes: [DeviceAddCloudScope] = []

    fileprivate var isCurrentDeviceAddContext: Bool {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              deviceAddScopes.allSatisfy({ $0.currentSpace != nil }) else { return false }
        if let siteId = operation.configurationSiteId, let siteMeshUUID {
            return SiteData.load(siteId: siteId)?.meshUUID == siteMeshUUID
        }
        return true
    }

    fileprivate func deferForDeviceAdd() {
        stopTimewait()
        isDeferredForDeviceAdd = true
        serializesDeviceAdd = true
    }

    fileprivate func appendCallback(_ callback: @escaping SyncHandleCallback) {
        let previous = handleCallback
        handleCallback = { handle, state in previous?(handle, state); callback(handle, state) }
    }

    fileprivate func receiveCoalescedState(_ state: CloudSynchronizationState) {
        guard self.state.rawValue != CloudSynchronizationState.cancel.rawValue else { return }
        self.state = state
        handleCallback?(self, state)
    }

    fileprivate func reloadDeviceAddSnapshot() -> Bool {
        guard let siteId = operation.configurationSiteId, let site = SiteData.load(siteId: siteId) else { return false }
        let oldSpaces = operation.spacesForDeviceAdd
        let spaces = oldSpaces.compactMap { old -> SpaceData? in
            guard let latest = SpaceData.load(siteId: siteId, spaceId: old.id).first,
                  latest.meshUUID == old.meshUUID, latest.meshNetworkId == old.meshNetworkId else { return nil }
            return latest
        }
        guard spaces.count == oldSpaces.count else { return false }
        operation = .syncSite(site: site, syncSpaces: spaces)
        return true
    }
    /// 等级
    var level: SyncLevel {
        didSet {
            guard case .wait = state, !isDeferredForDeviceAdd, !isCoalesced else {
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
    
    /// 初始化数据同步云端操作
    /// - Parameters:
    ///   - operation: 操作类型
    ///   - level: 等级
    ///   - callback: 状态回调
    init(operation: SyncOperation, level: SyncLevel, result: SyncHandleCallback?) {
        self.operation = operation
        self.siteMeshUUID = operation.configurationSiteMeshUUID
        self.level = level
        self.handleCallback = result
        self.deviceAddScopes = operation.spacesForDeviceAdd.map(DeviceAddCloudScope.init)
    }
    
    deinit {
//        print("deinit \(operation)")
    }
    
    /// 开始
    func start() {
        precondition(Thread.isMainThread)
        guard case .wait = state, !isCoalesced, mayStart?() != false else { return }
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
        // Admission, timer firing and mutations share the main queue. A queued timer
        // cannot cross a batch registration between its gate check and request start.
        let timer = DispatchSource.makeTimerSource(queue: .main)
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
        precondition(Thread.isMainThread)
        guard case .wait = state, !isCoalesced, mayStart?() != false else { return }
        guard isCurrentDeviceAddContext else { finishInvalidatedConfiguration(); return }
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
            guard self.isCurrentDeviceAddContext, !_Concurrency.Task<Never, Never>.isCancelled else {
                self.finishInvalidatedConfiguration(); return
            }
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
            // Entry cleanup waits while a receipt is pending. Prepare the normal
            // upload boundary after confirmation, even when no POST is needed.
            // Any cleanup edits must be included before deciding this sync is done.
            guard let api = await self.operation.getNetworkApi() else {
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
                self.finishExportFailure()
                return
            }
            guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
            guard isCurrentOperation() else { self.finishInvalidatedConfiguration(); return }
            if hadPending && !self.configurationSpaces.contains(where: { $0.needUploadCloud }) {
                let sitePending: Bool
                switch self.operation {
                case .syncSite(let site, _), .addSpaces(let site, _):
                    guard let current = SiteData.load(siteId: site.id),
                          let zones = try? SiteExtensionStore.load(current) else {
                        self.finishExportFailure()
                        return
                    }
                    // Zone cleanup persists its own pending generation without
                    // advancing the Site timestamp. Keep its prepared upload.
                    sitePending = current.needUploadCloud || zones.pending != nil
                default: sitePending = false
                }
                if !sitePending {
                    self.state = .successful
                    self.handleCallback?(self, self.state)
                    return
                }
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
                          contexts[id] != nil else {
                        result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
                        continue
                    }
                    if case .success = await SpaceConfigurationSafety.resumeUpload(space) {
                        if case .success = await SpaceConfigurationSafety.finishCloudRemovalUpload(space) {
                            confirmedConfigurationIds.insert(id)
                        } else {
                            result = .failure(SpaceConfigurationSafety.uploadUnconfirmed)
                        }
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
