//
//  String+Extension.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/3.
//

import Foundation

extension String {
    
    /// 判断是否数字
    func isPureNumandCharacters() -> Bool {
        let string = self.trimmingCharacters(in: NSCharacterSet.decimalDigits)
        return string.count > 0 ? false : true
    }
    
    /** 判断字符串是否都为空*/
    func isAllInputTextEmpty() -> Bool {
        var isEmpty = true
        
        let str = NSString.init(string: self)
        
        for index in 0..<str.length {
            let content = str.substring(with: NSRange.init(location: index, length: 1))
            if !content.elementsEqual(" ") {
                isEmpty = false
            }
        }
        
        return isEmpty
    }
    
    func byteLength() -> Int {
//        let enc = CFStringConvertEncodingToNSStringEncoding(.max)
        
        let data = self.data(using: .utf8)
//        [str dataUsingEncoding:enc];
        return data?.count ?? 0
    }
    
    /// 匹配是否包含中文
//    func validateContainsChineseT(content: String) -> Bool {
//        let regEx = ".+[\u4e00-\u9fa5].+" // @"^[\u4e00-\u9fa5].*" - ^为匹配中文开始
//        let predicate = NSPredicate(format: "SELF MATCHES %@", regEx)
//        return predicate.evaluate(withObject: content)
//    }
    /// 匹配是否包含中文
    func judgeStringIncludeChineseWord() -> Bool {
        
        for (_, value) in self.enumerated() {

            if ("\u{4E00}" <= value  && value <= "\u{9FA5}") {
                return true
            }
        }
        
        return false
    }
    
    
    /// 某个范围内截取
    /// - Parameter rangs: 范围
    public func subString(rang rangs:NSRange) -> String{
        var string = String()
        if(rangs.location >= 0) && (self.count >= (rangs.location + rangs.length)){
            let startIndex = self.index(self.startIndex,offsetBy: rangs.location)
            let endIndex = self.index(self.startIndex,offsetBy: (rangs.location + rangs.length))
            let subString = self[startIndex..<endIndex]
            string = String(subString)
        }
        return string
    }
    
}
