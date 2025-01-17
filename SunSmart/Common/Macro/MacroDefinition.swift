//
//  MacroDefinition.swift
//  nRFMeshDemo
//
//  Created by 袁科鸿 on 2022/11/14.
//

import UIKit

/** 屏幕宽度*/
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
/** 屏幕高度*/
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
/** 设备是否为iPhone X*/
//if #available(iOS 13.0, *) {

//} else {
let isIphoneX = StatusBarManager.statusBarFrame.size.height >= 44
//}
/** 导航条高度*/
//let kNavigationHeight = StatusBarManager.statusBarFrame.size.height + 44
let kNavigationHeight = kSafeAreaTopHeight + 44

/** tabbar高度*/
let kTabbarHeight = CGFloat(kSafeAreaBottomHeight + 44)

/// 导航栏右侧item边距
let navigationRightItemMargin = SCRXFrom(SCRXFrom(15.5)) //isIPad ? 20 : SCRXFrom(SCRXFrom(15.5))

/// 顶部导航栏边距
var kSafeAreaTopHeight: CGFloat {
    guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else {
        return 0 // 返回默认值，避免崩溃
    }
    return window.safeAreaInsets.top
}

//let kSafeAreaTopHeight = StatusBarManager.statusBarFrame.size.height
/** 底部边界值  iPhone X类型使用*/
let kSafeAreaBottomHeight = CGFloat(isIphoneX ? 34 : 0)
//if #available(iOS 13.0, *) {
let StatusBarManager = UIApplication.shared.windows.first!.windowScene!.statusBarManager!
//}

// 屏幕适配 (x)
func SCRXFrom(_ x : CGFloat) -> CGFloat {
    if isIPad {
        return x
    }
    return x * SCREEN_WIDTH / 375.0
}

// 屏幕适配 (y)
func SCRYFrom(_ y : CGFloat) -> CGFloat {
    guard isIphoneX else {
        return y
    }
    return y * SCREEN_HEIGHT / 812.0
//    (isIphoneX ? 736 : SCREEN_HEIGHT) / 667.0 * y
}

func FontFit(_ size: CGFloat) -> CGFloat {
    return size * min(SCREEN_HEIGHT / 812.0, 1.05)
}

// 屏幕等比适配 (y)
func SCRYFit(_ y : CGFloat) -> CGFloat {
    return SCREEN_HEIGHT / 812.0 * y
}

let isIPad = UIDevice.current.model == "iPad"

//let BACKGROUND_COLOR = RGB(248, 250, 252)
//背景色
let Background_Color = RGB(248, 250, 252)
// 白色
let White_Color = UIColor.white
/**普通文本黑色*/
let TextBlack_Color = RGB(30, 35, 41)

let TextBlack_Color1 = RGB(13, 16, 36)

let Title_Color = RGB(64, 79, 102)

/// 常规的黑色
let Default_Black_Color = RGB(28, 28, 35)

/// 描述文字颜色
let Message_Color = RGB(134, 138, 160)

/// 主色
let Bar_Color = RGB(102, 103, 171)
/// 线条颜色
let Line_Color = RGB(243, 243, 243)    //RGB(126, 126, 126, 0.1)
let Line_Color1 = RGB(236, 236, 236)

/// 按钮蓝色
let Blue_Color = RGB(0, 122, 255)
/// 按钮红色
let Red_Color = RGB(235, 78, 78)

let SubText_Color = RGB(100, 116, 139)

let Chart_Text_Color = RGB(72, 72, 74)
/// 绿色
let Green_Color = RGB(0, 209, 124, 1)

/// RGB颜色
func RGB(_ red:Int,_ green:Int,_ blue:Int, _ alpha:CGFloat=1) -> UIColor {
    return UIColor.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: alpha)
}


/************************* 字体 **************************/

/** 轻微加粗字体*/
let FontName_Medium = "PingFangSC-Medium"

/** 粗体*/
let FontName_Bold = "PingFangSC-Semibold"

func FONTS(_ size : CGFloat) -> UIFont {
    return UIFont.systemFont(ofSize: size)
}
func Font_Medium_Size(_ size : CGFloat) -> UIFont {
    return UIFont.init(name: FontName_Medium, size: size) ?? UIFont()
}
func Font_Bold_Size(_ size : CGFloat) -> UIFont {
    return UIFont.init(name: FontName_Bold, size: size) ?? UIFont()
}

/// 使用协议
let termsOfUseUrlStr = "https://srdocs.gitee.io/privacypolicy/#/ble/en"
/// 隐私政策
let privacyPolicyUrlStr = "https://srdocs.gitee.io/privacypolicy/#/ble/en"
