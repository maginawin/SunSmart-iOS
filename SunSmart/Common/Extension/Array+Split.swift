//
//  Array+Split.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/10.
//

import Foundation

extension Array where Element == Int {
    
    /// 将一维数组按顺序分割成二维数组，数据不连续则分割
    func splitArray() -> [[Int]] {
        guard !self.isEmpty else { return [] }
        
        var result: [[Int]] = []
        var currentSubarray: [Int] = [self[0]]
        
        for i in 1..<self.count {
            if self[i] == self[i-1] + 1 {
                currentSubarray.append(self[i])
            } else {
                result.append(currentSubarray)
                currentSubarray = [self[i]]
            }
        }
        result.append(currentSubarray)
        return result
    }

}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
