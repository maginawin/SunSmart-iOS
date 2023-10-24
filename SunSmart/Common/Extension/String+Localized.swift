//
//  String+Localized.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/18.
//

import Foundation

extension String {
    
    var localizedString: String {
        return NSLocalizedString(self, comment: "")
    }
    
}
