//
//  EnergyTestData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/28.
//

import Foundation


struct EnergyPieData {
    /// 名称
    let name: String
    /// 颜色
    let color: UIColor
    /// 比例 0~1
    let percent: Double
    /// 能耗数据
    let data: String
}

struct EnergyTestData {
    
    static func generateRandomPercentages(count: Int, minimum: Double = 0.05) -> [Double] {
        guard count > 0 else { return [] }
        
        // 1. 先给每个占用一部分最小值
        let base = Array(repeating: minimum, count: count)
        
        // 2. 剩余部分随机分配
        let remaining = 1.0 - (minimum * Double(count))
        var randoms: [Double] = (0..<count).map { _ in Double.random(in: 0...1) }
        let randomTotal = randoms.reduce(0, +)
        randoms = randoms.map { $0 / randomTotal * remaining }
        
        // 3. 合并最小值和随机分配
        var result = zip(base, randoms).map(+)
        
        // 4. 校正误差
        let correction = 1.0 - result.reduce(0, +)
        if let index = result.indices.randomElement() {
            result[index] += correction
        }
        
        return result
    }

    static func smartReorderEntryPicDatas(_ picDatas: [EnergyPieData], smallThreshold: Double = 0.05) -> [EnergyPieData] {
        guard picDatas.count > 2 else { return picDatas }
        
        var big = picDatas.filter({ $0.percent >= smallThreshold }).sorted(by: { $0.percent > $1.percent })
        var small = picDatas.filter { $0.percent < smallThreshold }.sorted(by: { $0.percent > $1.percent })
        
        var result: [EnergyPieData] = []
        
        while !big.isEmpty || !small.isEmpty {
            if let bigValue = big.first {
                result.append(bigValue)
                big.removeFirst()
            }
            if let smallValue = small.first {
                result.append(smallValue)
                small.removeFirst()
            }
        }
        
        return result
    }
    
}
