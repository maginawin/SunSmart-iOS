//
//  DeviceAudioManager.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/12.
//

import Foundation
import AVFoundation

class DeviceAudioManager {
    
    /// 音频类型
    enum AudioType {
        
        /// 音频文件url
        var fileURL: URL? {
            var fileName: String!
            switch self {
            case .deviceAdd:
                fileName = "device_add"
            case .deviceReset:
                fileName = "device_reset"
            }
            return Bundle.main.url(forResource: fileName, withExtension: "mp3")
        }
        
        /// 设备添加音效
        case deviceAdd
        /// 设备重置音效
        case deviceReset
    }
    
    var audioPlayer: AVAudioPlayer?
    
    static let manager = DeviceAudioManager()
    
    /// 开始播放音频
    func startAudio(type: AudioType, volume: Int = 50) throws {
        
        audioPlayer?.stop()
        guard let url = type.fileURL else {
            throw NSError(domain: "未找到资源", code: 100)
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 正确配置（忽略静音开关）
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = Float(volume) / 100.0
            audioPlayer?.play()
        } catch {
            throw error
        }
    }
    
    /// 停止播放音频
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    /// 震动
    func vibration() {
        // 触发标准短震动
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
}
