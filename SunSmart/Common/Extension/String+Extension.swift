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
    
    /// 根据地区编码获取是否中国大陆
    static func isChina(regionCode: String) -> Bool {
        return regionCode == "CN"
    }

    /// 根据地区编码获取是否北美
    static func isNorthAmerica(regionCode: String) -> Bool {
        let northAmericaRegionCodes: Set<String> = ["US", "CA", "MX"]
        return northAmericaRegionCodes.contains(regionCode)
    }

    /// 根据地区编码获取是否欧洲
    static func isEurope(regionCode: String) -> Bool {
        let europeRegionCodes: Set<String> = [
            "AL", "AD", "AM", "AT", "AZ", "BY", "BE", "BA", "BG", "HR", "CY", "CZ", "DK",
            "EE", "FI", "FR", "GE", "DE", "GR", "HU", "IS", "IE", "IT", "KZ", "XK", "LV",
            "LI", "LT", "LU", "MT", "MD", "MC", "ME", "NL", "MK", "NO", "PL", "PT", "RO",
            "RU", "SM", "RS", "SK", "SI", "ES", "SE", "CH", "TR", "UA", "GB", "VA"
        ]
        return europeRegionCodes.contains(regionCode)
    }
    
    // 生成一个包含4个随机数字字符的字符串
    static func generateRandomNumberString(length: Int = 4) -> String {
        let digits = "0123456789"
        var result = ""
        
        for _ in 0..<length {
            if let randomDigit = digits.randomElement() {
                result.append(randomDigit)
            }
        }
        return result
    }
    
    // 生成一个包含4个随机字母+数字的字符串
    static func generateRandomString(length: Int = 4) -> String {
        let lettersAndNumbers = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in lettersAndNumbers.randomElement()! })
    }
    
    /// 是否有效邀请码
    func isValidInvitationCode() -> Bool {
        let pattern = "^[A-Z\\d]{8}$"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
    
}


