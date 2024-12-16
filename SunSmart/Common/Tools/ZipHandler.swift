//
//  ZipHandler.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/18.
//

import Foundation
import ZIPFoundation

struct FirmwareZipData {
    /// 固件id
    let firmwareId: Data
    /// 固件版本
    let firmwareVersion: String
    /// 升级来源 1：app
    let coreType: Int
    /// 升级镜像索引
    let imageIndex: Int
    /// 节点数据hash
    let compositionHash: Data
    /// element数量
    let elementCount: Int
    /// 固件数据
    let firmwareData: Data
}

class ZipHandler {

    /// 下载 Zip 文件并处理解压
    static func downloadAndHandleZip(from url: URL, completion: @escaping (Result<FirmwareZipData, Error>) -> Void) {
        // 1. 下载文件
        downloadZip(from: url) { result in
            switch result {
            case .success(let zipData):
                // 2. 解压并处理文件
                do {
                    let data = try self.handleZipData(zipData)
                    completion(.success(data))
                } catch let error {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// 下载 Zip 文件并获取 Data 数据
    private static func downloadZip(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10  // 设置请求的超时时间
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(NSError(domain: "DownloadError", code: -1, userInfo: nil)))
                    return
                }
                
                completion(.success(data))
            }
        }
        task.resume()
    }

    /// 处理 Zip 数据
    static func handleZipData(_ zipData: Data) throws -> FirmwareZipData {
        // 获取临时目录路径
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let zipFileURL = tempDirectoryURL.appendingPathComponent("temp.zip")
        
        // 防止异常未删除之前数据导致流程失败
        if FileManager.default.fileExists(atPath: zipFileURL.path) {
            // 删除临时文件目录
            try FileManager.default.removeItem(at: zipFileURL)  // 删除下载的 zip 文件
        }
        
        // 将下载的 Data 写入临时 zip 文件
        try zipData.write(to: zipFileURL)
        
        // 删除解压目录
        let destinationURL = tempDirectoryURL.appendingPathComponent("unzipped")
        // 防止异常未删除之前数据导致流程失败
        
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)  // 删除解压后的临时目录
        }
        
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.unzipItem(at: zipFileURL, to: destinationURL)
        
        // 处理解压后的文件 (这里可以根据需求处理解压后的内容)
        let data = try handleUnzippedFiles(at: destinationURL)
        
        // 删除临时文件和解压目录
        try FileManager.default.removeItem(at: zipFileURL)  // 删除下载的 zip 文件
        try FileManager.default.removeItem(at: destinationURL)  // 删除解压后的临时目录
        return data
    }

    /// 处理解压后的文件
    private static func handleUnzippedFiles(at destinationURL: URL) throws -> FirmwareZipData {
        // 遍历解压目录的内容，进行文件处理
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: destinationURL.path)
        
        // 配置数据
        var configJson: [String: Any]?
        // 固件包
        var firmwareData: Data?
        
        for file in files {
            let filePath = destinationURL.appendingPathComponent(file)
//            print("解压后的文件路径: \(filePath)")
            // 根据文件的扩展名处理文件
            if filePath.pathExtension == "json" {
                // 处理配置文件
                let data = try Data(contentsOf: filePath)
                configJson = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else if filePath.pathExtension == "bin" {
                // 处理固件文件
                let fileData = try Data(contentsOf: filePath)
//                print("固件包大小：\(fileData.count)")
                firmwareData = fileData
            }
        }
        guard let config = configJson, var firmwareIdStr = config["firmware_id"] as? String, let hash = config["comp_hash"] as? String, let elementCount = config["element_count"] as? Int, let imageIndex = config["image_id"] as? Int, let firmwareData = firmwareData else {
            throw NSError(domain: "Data exception", code: -1)
        }
        // 固件id 1.2.1+0  => 0x01 02 0001 00000000
        firmwareIdStr = firmwareIdStr.replacingOccurrences(of: "v", with: "")
        let firmwareIdArray = firmwareIdStr.components(separatedBy: "+")
        let versionArray = firmwareIdArray.first?.components(separatedBy: ".")
        guard firmwareIdArray.count >= 1, versionArray?.count == 3 else {
            throw NSError(domain: "Data exception", code: -1)
        }
        
        var firmwareId = Data(count: 8)
        let main = UInt8(versionArray![0]) ?? 0
        let middle = UInt8(versionArray![1]) ?? 0
        let sub = UInt16(versionArray![2]) ?? 0
        var build: UInt32 = 0
        if firmwareIdArray.count == 2 {
            build = UInt32(firmwareIdArray[1]) ?? 0
        }
        
        
        firmwareId.writeBits(value: main, numBits: 8, atOffset: 0)
        firmwareId.writeBits(value: middle, numBits: 8, atOffset: 8)
        firmwareId.writeBits(value: sub, numBits: 16, atOffset: 16)
        firmwareId.writeBits(value: build, numBits: 32, atOffset: 32)
        
        // 升级来源 1: App 其它值目前不存在
        let coreType = config["core_type"] as? Int ?? 1
        
        
        let data = FirmwareZipData(firmwareId: firmwareId, firmwareVersion: firmwareIdArray.first ?? "", coreType: coreType, imageIndex: imageIndex, compositionHash: Data(hex: hash).turnOver(), elementCount: elementCount, firmwareData: firmwareData)
        return data
    }
}
