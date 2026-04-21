//
//  EmerFireCardPosition.swift
//  SunSmart
//
//  Created by OpenAI on 2026/4/20.
//

import UIKit

enum EmerFireCardPosition {
    case single
    case top
    case middle
    case bottom

    var topInset: CGFloat {
        switch self {
        case .single, .top:
            return SCRYFrom(4)
        case .middle, .bottom:
            return 0
        }
    }

    var bottomInset: CGFloat {
        switch self {
        case .single, .bottom:
            return SCRYFrom(4)
        case .top, .middle:
            return 0
        }
    }

    var maskedCorners: CACornerMask {
        switch self {
        case .single:
            return [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .top:
            return [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .middle:
            return []
        case .bottom:
            return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }

    var showsSeparator: Bool {
        switch self {
        case .single, .bottom:
            return false
        case .top, .middle:
            return true
        }
    }
}
