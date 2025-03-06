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
        }
    }
    
    /// 同步site  syncSpaces:需要同时同步的spaces
    case syncSite(site: SiteData, syncSpaces: [SpaceData] = [])
    /// 同步space
    case syncSpace(space: SpaceData)
    /// 添加spaces
    case addSpaces(site: SiteData, spaces: [SpaceData])
    
    /// 判断操作是否相等
    static func == (lhs: SyncOperation, rhs: SyncOperation) -> Bool {
        
        guard lhs.type == rhs.type else {
            return false
        }
        switch lhs {
        case .syncSite(let site, let syncSpaces):
            if case .syncSite(let rhsSite, let rhsSyncSpaces) = rhs {
                // 后面同步的spaces包含上一个同步的所有spaces
                return site.id == rhsSite.id && (!rhsSyncSpaces.contains(where: { rhsSpace in !syncSpaces.contains(where: { $0.id == rhsSpace.id }) }) || syncSpaces.isEmpty)
            }
        case .syncSpace(let space):
            if case .syncSpace(let rhsSpace) = rhs {
                return space.id == rhsSpace.id
            }
        case .addSpaces(let site, _):
            if case .addSpaces(let rhsSite, _) = rhs {
                return site.id == rhsSite.id
            }
        }
        return false
    }
    
    func getNetworkApi() async -> NetowrkReqeustApi {
        switch self {
        case .syncSite(let site, let syncSpaces):
            if site.uploadCloud {
                return .siteUpload(siteData: await site.export(spaceIds: syncSpaces.map({ $0.id })))
            }else {
                // 获取最后分配的设备地址
                let maxAddress = MeshAPI.getTheUsedDeviceAddresses(meshUUID: site.meshUUID).max()
                return .siteAdd(siteData: await site.export(spaceIds: syncSpaces.map({ $0.id })), useDeivceAddressNum: Int(maxAddress ?? 0))
            }
        case .syncSpace(let space):
            return .spaceUpload(siteId: space.siteId, spaceData: await space.export())
        case .addSpaces(let site, let spaces):
            
            let siteData = await site.export(spaceIds: spaces.map({ $0.id }))
            return .siteUpload(siteData: siteData)
//                .spacesAdd(siteId: site.id, spaceDatas: spaceDicts)
        }
    }
    
}

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

class CloudSynchronizationManager {
    
    static let shared = CloudSynchronizationManager()
    
    private var syncHandles: [CloudSynchronizationHandle] = []
    
    private let mutex = DispatchQueue(label: "cloudSyncMutex")
    
    weak var delegate: CloudSynchronizationManagerDelegate?
    
    /// 添加同步云端数据操作
    /// - Parameters:
    ///   - operation: 操作数据类型
    ///   - level: 同步等级
    func addSynchronizationHandle(operation: SyncOperation, level: SyncLevel) {
        
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
            }
        })
//        DispatchQueue.global().async {
            self.mutex.sync {
                self.syncHandles.append(handle)
            }
//        }
        
        
        handle.start()
    }
    
    /// 取消同步操作
    func cancelSynchronizationHandle(operation: SyncOperation) {
        
        if let lastHandleIndex = syncHandles.firstIndex(where: { $0.operation == operation }) {
            syncHandles[lastHandleIndex].cancel()
            self.mutex.sync {
               _ = syncHandles.remove(at: lastHandleIndex)
            }
        }
    }
    
    /// 取消site相关的同步操作
    func cancelSynchronizationHandle(site: SiteData) {
        
        // 获取site相关同步操作
        let handles = syncHandles.filter({ handle in
            switch handle.operation {
            case .syncSite(let site, _):
                return site.id == site.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let site, _):
                return site.id == site.id
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
    
    /// 取消space相关的同步操作
    func cancelSynchronizationHandle(space: SpaceData) {
        
        // 获取space相关同步操作
        if let handle = syncHandles.first(where: { handle in
            switch handle.operation {
            case .syncSite(_, let syncSpaces):
                return syncSpaces.contains(where: { $0.id == space.id })
            case .syncSpace(let syncSpace):
                return space.id == syncSpace.id
            case .addSpaces(_, let spaces):
                return spaces.contains(where: { $0.id == space.id })
            }
        }) {
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
    func getSitesCurrentSyncState() -> CloudSynchronizationHandle.State? {
        
        // 获取site相关同步操作
        let siteHandles = syncHandles.filter({ handle in
            if case .syncSite = handle.operation {
                return true
            }
            return false
        })
        
        var state: CloudSynchronizationHandle.State?
        // 进行中
        if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.inProgress.rawValue }) {
            state = .inProgress
        }else if let failedHandle = siteHandles.first(where: { // 操作全部完成并存在失败
            if case .failure = $0.state { return true }
            return false
        }) {
            state = failedHandle.state
        }else if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.successful.rawValue }) { // 操作全部完成并全部成功
            state = .successful
        }else if siteHandles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.wait.rawValue }) { // 操作全部都在等待
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
            case .syncSite(let site, _):
                return site.id == site.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let site, _):
                return site.id == site.id
            }
        })
        return handle
    }
    
    /// 根据site数据获取当前同步状态（复合状态可能包含下级多个space状态）
    /// - Parameter site: site
    /// - Returns: 当前同步操作
    func getSiteCurrentSyncState(_ site: SiteData) -> CloudSynchronizationHandle.State? {
        
        // 获取site/space相关同步操作
        let handles = syncHandles.filter({ handle in
            switch handle.operation {
            case .syncSite(let syncSite, _):
                return site.id == syncSite.id
            case .syncSpace(let space):
                return space.siteId == site.id
            case .addSpaces(let syncSite, _):
                return site.id == syncSite.id
            }
        })
        
        var state: CloudSynchronizationHandle.State?
        // 进行中
        if handles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.inProgress.rawValue }) {
            state = .inProgress
        }else if let failedHandle = handles.first(where: { // 操作全部完成并存在失败
            if case .failure = $0.state { return true }
            return false
        }) {
            state = failedHandle.state
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.successful.rawValue }) { // 操作全部完成并全部成功
            state = .successful
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.wait.rawValue }) { // 操作全部都在等待
            state = .wait
        }else if handles.contains(where: { $0.state.rawValue == CloudSynchronizationHandle.State.cancel.rawValue }) { // 取消
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
            }
        })
        return handle
    }
    
}

class CloudSynchronizationHandle: NSObject {
    
    /// 同步操作回调   state：状态
    typealias SyncHandleCallback = ((CloudSynchronizationHandle, State)->Void)
    
    typealias AsyncTask = _Concurrency.Task
    
    /// 状态
    enum State {
        
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
    var state: State = .wait
    /// 等待定时器
    private var waitTimer: Timer?
    /// 网络请求操作
    private var requestHandle: Cancellable?
    /// 同步数据操作回调
    private var handleCallback: SyncHandleCallback?
    
    
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
            }
            DispatchQueue.main.async {
                self.handleCallback?(self, self.state)
            }
            return
        }
        startTimewait()
    }
    
    /// 取消
    func cancel() {
        stopTimewait()
        requestHandle?.cancel()
        state = .cancel
        DispatchQueue.main.async {
            self.handleCallback?(self, self.state)
        }
    }
    
    /// 进入计时
    private func startTimewait() {
        if let timer = waitTimer {
            timer.invalidate()
        }
        waitTimer = Timer.scheduledTimer(withTimeInterval: level.interval, repeats: false, block: {[weak self] _ in
            guard let self = self else { return }
            self.syncOperation()
        })
        RunLoop.current.add(waitTimer!, forMode: .common)
    }
    
    /// 停止计时
    private func stopTimewait() {
        waitTimer?.invalidate()
        waitTimer = nil
    }
    
    /// 开始同步到服务器
    func syncOperation() {
        if waitTimer?.isValid ?? false {
            waitTimer?.invalidate()
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
        AsyncTask {
            let api = await self.operation.getNetworkApi()
            requestHandle = NetworkRequest.shared.request(api) {[weak self] result in
                guard let self = self else { return }
                self.requestHandle = nil
                switch result {
                case .success(let response):
                    self.state = .successful
                    // 更新缓存
                    switch self.operation {
                    case .syncSite(let site, let syncSpaces):
                        if !site.uploadCloud { // 首次上传site，更新owner的地址资源数据（将地址提交到服务器分配，并且服务器重分配地址给owner）
                           if let provisionerData = JSON(response)["data"]["addrLists"].dictionaryObject {
                                site.setOwnerProvisioner(addressData: provisionerData)
                                
                                // 更新完服务器分配地址后再次提交到服务器，首次上传的site还是最初mesh分配的地址
//                                site.lastUpdate = Int64(Date().timeIntervalSince1970)
//                                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                            }
                        }
                        site.lastUploadCloudTimestamp = site.lastUpdate
                        site.syncCloudError = nil
                        site.save()
                        syncSpaces.forEach({
                            $0.lastUploadCloudTimestamp = $0.lastUpdate
                            $0.syncCloudError = nil
                            $0.save()
                        })
                        
                    case .addSpaces(let site, let spaces):
                        site.lastUploadCloudTimestamp = site.lastUpdate
                        site.syncCloudError = nil
                        spaces.forEach({
                            $0.lastUploadCloudTimestamp = $0.lastUpdate
                            $0.syncCloudError = nil
                            $0.save()
                        })
                        site.save()
                    case .syncSpace(let space):
                        space.lastUploadCloudTimestamp = space.lastUpdate
                        space.syncCloudError = nil
                        space.save()
                    }
                    
                case .failure(let error):
                    self.state = .failure(error: error)
                    // 更新缓存
                    switch self.operation {
                    case .syncSite(let site, let syncSpaces):
                        site.syncCloudError = error
                        site.save()
                        syncSpaces.forEach({
                            $0.syncCloudError = error
                            $0.save()
                        })
                    case .addSpaces(_, let spaces):
                        spaces.forEach({
                            $0.syncCloudError = error
                            $0.save()
                        })
//                        site.save()
                    case .syncSpace(let space):
                        space.syncCloudError = error
                        space.save()
                    }
                    
                    
                }
                DispatchQueue.main.async {
                    self.handleCallback?(self, self.state)
                }
            }
        }
    }
    
}
