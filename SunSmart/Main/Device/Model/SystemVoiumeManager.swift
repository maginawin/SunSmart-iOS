//
//  SystemVoiumeManager.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/9.
//

import Foundation
import AVFAudio

class SystemVolumeManager: NSObject {
    static let shared = SystemVolumeManager()
    
    @objc dynamic private(set) var currentVolume: Float = AVAudioSession.sharedInstance().outputVolume
    
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
    
    var onVolumeChanged: ((Float) -> Void)?
    
    override init() {
        super.init()
     
    }
    
    /// 开始监听系统音量
    func startObserveVolume() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeChanged(_:)),
            name: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVolume),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        systemVolumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new], changeHandler: {[weak self] _, change in
            guard let self = self else { return }
            guard let newVolume = change.newValue else { return }
            DispatchQueue.main.async {
                self.currentVolume = newVolume
                self.onVolumeChanged?(newVolume)
            }
        })
        
    }
    
    /// 停止监听系统音量
    func stopObserveVolume() {
        NotificationCenter.default.removeObserver(self)
        systemVolumeObservation = nil
    }
    
    @objc private func volumeChanged(_ notification: Notification) {
        if let volume = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float {
            currentVolume = volume
            onVolumeChanged?(volume)
        }
    }
    
    @objc private func refreshVolume() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true, options: [])
        currentVolume = session.outputVolume
        onVolumeChanged?(currentVolume)
    }
}

//import AVFoundation
//import UIKit
//import MediaPlayer // 如需使用 MPVolumeView 则导入
//
//class SystemVolumeManager: NSObject {
//    static let shared = SystemVolumeManager()
//    
//    @objc dynamic private(set) var currentVolume: Float = 0.0
//    private let audioSession = AVAudioSession.sharedInstance()
//    private var volumeObservation: NSKeyValueObservation?
//    var onVolumeChanged: ((Float) -> Void)?
//    
//    override init() {
//        super.init()
//        setupAudioSession()
//        setupNotifications()
//        setupVolumeObservation()
//    }
//    
//    deinit {
//        volumeObservation?.invalidate()
//        NotificationCenter.default.removeObserver(self)
//    }
//    
//    // MARK: - 初始化设置
//    private func setupAudioSession() {
//        do {
//            // 设置音频会话类别，根据你的应用需求选择
//            // 例如，如果你只需要播放声音而不需要录音，且希望与其他音频混合，可以使用 `.ambient`
//            // 如果你的音频需要持续后台播放，请选择 `.playback` 并在 Info.plist 中声明后台音频模式
//            try audioSession.setCategory(.ambient, mode: .default, options: .mixWithOthers)
//            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation]) // 激活会话
//            currentVolume = audioSession.outputVolume // 初始化当前音量
//        } catch {
//            print("Failed to set up audio session: \(error)")
//        }
//    }
//    
//    private func setupNotifications() {
//        // 监听应用前后台切换
//        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
//        
//        // 监听音频会话中断（如来电、警报）
//        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)
//        // 监听音频路由变化（如插入/拔出耳机）
//        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
//    }
//    
//    private func setupVolumeObservation() {
//        // 观察系统音量变化
//        volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] (session, change) in
//            guard let self = self, let newVolume = change.newValue else { return }
//            DispatchQueue.main.async {
//                self.updateCurrentVolume(newVolume)
//            }
//        }
//    }
//    
//    // MARK: - 通知处理
//    @objc private func appDidBecomeActive() {
//        // 应用返回前台时，重新激活音频会话并刷新音量
//        do {
//            // 即使之前已激活，再次调用 setActive(true) 也可以帮助刷新状态
//            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
//            refreshSystemVolume() // 强制刷新一次音量
//        } catch {
//            print("Failed to activate audio session on become active: \(error)")
//        }
//    }
//    
//    @objc private func appWillResignActive() {
//        // 应用进入后台时，通常不需要停用音频会话，除非有特殊需求
//        // 保持激活状态可以更好地恢复，但请根据你的应用场景决定
//        // do {
//        //     try audioSession.setActive(false)
//        // } catch {
//        //     print("Failed to deactivate audio session on resign active: \(error)")
//        // }
//    }
//    
//    @objc private func handleAudioSessionInterruption(notification: Notification) {
//        guard let userInfo = notification.userInfo,
//              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
//              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else { return }
//        
//        switch interruptionType {
//        case .began:
//            // 中断开始，音频已停止
//            print("Audio session interruption began.")
//        case .ended:
//            // 中断结束，应重新激活音频会话
//            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
//                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
//                if options.contains(.shouldResume) {
//                    do {
//                        try audioSession.setActive(true)
//                        refreshSystemVolume()
//                    } catch {
//                        print("Failed to resume audio session after interruption: \(error)")
//                    }
//                }
//            }
//        @unknown default:
//            break
//        }
//    }
//    
//    @objc private func handleAudioSessionRouteChange(notification: Notification) {
//        // 音频路由变化时也刷新音量
//        refreshSystemVolume()
//    }
//    
//    // MARK: - 音量刷新与更新
//    func refreshSystemVolume() {
//        // 强制从系统获取最新音量
//        let latestVolume = audioSession.outputVolume
//        updateCurrentVolume(latestVolume)
//    }
//    
//    private func updateCurrentVolume(_ volume: Float) {
//        // 避免不必要的回调
//        if currentVolume != volume {
//            currentVolume = volume
//            onVolumeChanged?(volume)
//            print("System volume updated to: \(volume)")
//        }
//    }
//    
//    // MARK: - 公共方法
//    func startMonitoring() {
//        // 确保观察者是设置的
//        if volumeObservation == nil {
//            setupVolumeObservation()
//        }
//        // 刷新一次当前音量
//        refreshSystemVolume()
//    }
//    
//    func stopMonitoring() {
//        volumeObservation?.invalidate()
//        volumeObservation = nil
//    }
//}
//
//// MARK: - 使用示例
//extension SystemVolumeManager {
//    // 简便的静态方法
//    static func getCurrentVolume() -> Float {
//        return AVAudioSession.sharedInstance().outputVolume
//    }
//    
//    static func observeVolumeChanges(_ handler: @escaping (Float) -> Void) -> NSKeyValueObservation {
//        return AVAudioSession.sharedInstance().observe(\.outputVolume) { session, change in
//            guard let newVolume = change.newValue else { return }
//            handler(newVolume)
//        }
//    }
//}
