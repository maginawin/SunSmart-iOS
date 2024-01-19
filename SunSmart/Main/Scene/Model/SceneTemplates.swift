//
//  SceneTemplates.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import Foundation

/// 模板大类
enum TemplateMainType {
    /// 常用
    case frequentlyUsed
    /// 办公室
    case office
    /// 学校
    case school
    /// 医疗
    case medicalTreatment
    /// 工业
    case industry
    /// 超市
    case supermarket
}

/// 模板场景类型
enum TemplateSceneType {
    //******* 常用 ******/
    /// 全开
    case allOn
    /// 全关
    case allOff
    /// 半亮
    case halfBright
    /// 背景光
    case backlight
    //******* 办公室 ******/
    /// 演示
    case ppt
    /// 演讲
    case lecture
    /// 会议
    case conference
    /// 会谈
    case conversation
    /// 工作
    case work
    /// 空闲
    case vacant
    /// 下班(办公室)
    case getOffWork
    /// 正常
    case normal
    //******* 学校 ******/
    /// 上课
    case inClass
    /// 课间
    case `break`
    /// 投影
    case projection
    //******* 医疗 ******/
    /// 夏季
    case summer
    /// 冬季
    case winter
    /// 自然
    case natural
    /// 明亮
    case bright
    /// 舒缓
    case relaxing
    /// 休息
    case rest
    //******* 工业 ******/
    /// 预备上班
    case prepareWork
    /// 上班
    case industryWork
    /// 休息（工业）
    case industryRest
    /// 下班（工业）
    case industryOffWork
    //******* 超市 ******/
    /// 准备营业
    case prepareBusiness
    /// 正常营业
    case regular
    /// 人流高峰
    case peakTraffic
    /// 人流低谷
    case lowTraffic
    /// 打烊
    case close
}

/// 场景模板大类
struct SceneMainTemplate {
    
    /// 类型
    let mainType: TemplateMainType
    /// 标题
    let title: String
    /// 场景模板
    let sceneTemplates: [SceneTemplate]
//    var isShow: Bool = false
    
    init(mainType: TemplateMainType) {
        self.mainType = mainType
        var title = ""
        var sceneTypes: [TemplateSceneType] = []
        switch mainType {
        case .frequentlyUsed:
            title = "templates_frequently_used".localizedString
            sceneTypes = [.allOn, .allOff, .halfBright, .backlight]
        case .office:
            title = "templates_office".localizedString
            sceneTypes = [.ppt, .lecture, .conference, .conversation, .work, .vacant, .getOffWork, .normal]
        case .school:
            title = "templates_school".localizedString
            sceneTypes = [.inClass, .break, .projection]
        case .medicalTreatment:
            title = "templates_medical_treatment".localizedString
            sceneTypes = [.summer, .winter, .natural, .bright, .relaxing, .rest]
        case .industry:
            title = "templates_industry".localizedString
            sceneTypes = [.prepareWork, .industryWork, .industryRest, .industryOffWork]
        case .supermarket:
            title = "templates_supermarket".localizedString
            sceneTypes = [.prepareBusiness, .regular, .peakTraffic, .lowTraffic, .close]
        }
        self.title = title
        self.sceneTemplates = sceneTypes.map({ SceneTemplate(mainType: mainType, sceneType: $0) })
    }
    
    /// 场景模板
    struct SceneTemplate {
        /// 场景参数
        struct SceneParameter {
            /// 亮度
            let lightness: Int
            /// 色温
            let cct: Int
        }
        
        let mainType: TemplateMainType
        /// 使用场景类型
        let sceneType: TemplateSceneType
        /// 标题
        let title: String
        /// 图标id
        let imageId: Int
        /// 参数点
        let parameters: [SceneParameter]
        
        init(mainType: TemplateMainType, sceneType: TemplateSceneType) {
            self.mainType = mainType
            self.sceneType = sceneType
            switch sceneType {
                //******* 常用 ******/
            case .allOn:
                self.title = "templates_all_on".localizedString
                self.imageId = 2
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            case .allOff:
                self.title = "templates_all_off".localizedString
                self.imageId = 5
                self.parameters = [
                    SceneParameter(lightness: 0, cct: 5000)
                ]
            case .halfBright:
                self.title = "templates_half_bright".localizedString
                self.imageId = 3
                self.parameters = [
                    SceneParameter(lightness: 50, cct: 5000)
                ]
            case .backlight:
                self.title = "templates_backlight".localizedString
                self.imageId = 4
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000)
                ]
                //******* 办公室 ******/
            case .ppt:
                self.title = "templates_ppt".localizedString
                self.imageId = 6
                self.parameters = [
                    SceneParameter(lightness: 0, cct: 5000),
                    SceneParameter(lightness: 20, cct: 5000),
                    SceneParameter(lightness: 80, cct: 5000)
                ]
            case .lecture:
                self.title = "templates_lecture".localizedString
                self.imageId = 7
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000),
                    SceneParameter(lightness: 60, cct: 5000)
                ]
            case .conference:
                self.title = "templates_conference".localizedString
                self.imageId = 17
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            case .conversation:
                self.title = "templates_conversation".localizedString
                self.imageId = 16
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5500),
                    SceneParameter(lightness: 60, cct: 5000)
                ]
            case .work:
                self.title = "templates_work".localizedString
                self.imageId = 12
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5500)
                ]
            case .vacant:
                self.title = "templates_vacant".localizedString
                self.imageId = 10
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5500)
                ]
            case .getOffWork: // 下班（办公室）
                self.title = "templates_go_to_work".localizedString
                self.imageId = 26
                self.parameters = [
                    SceneParameter(lightness: 0, cct: 5000)
                ]
            case .normal:
                self.title = "templates_normal".localizedString
                self.imageId = 12
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            //******* 学校 ******/
            case .inClass:
                self.title = "templates_in_class".localizedString
                self.imageId = 19
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            case .break:
                self.title = "templates_break".localizedString
                self.imageId = 20
                self.parameters = [
                    SceneParameter(lightness: 80, cct: 4000)
                ]
            case .projection:
                self.title = "templates_projection".localizedString
                self.imageId = 21
                self.parameters = [
                    SceneParameter(lightness: 0, cct: 5000),
                    SceneParameter(lightness: 20, cct: 5000),
                    SceneParameter(lightness: 80, cct: 5000)
                ]
                //******* 医疗 ******/
            case .summer:
                self.title = "templates_summer".localizedString
                self.imageId = 15
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 6000),
                ]
            case .winter:
                self.title = "templates_winter".localizedString
                self.imageId = 13
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 3000),
                ]
            case .natural:
                self.title = "templates_natural".localizedString
                self.imageId = 14
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 4500),
                ]
            case .bright:
                self.title = "templates_bright".localizedString
                self.imageId = 2
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5500)
                ]
            case .relaxing:
                self.title = "templates_relaxing".localizedString
                self.imageId = 22
                self.parameters = [
                    SceneParameter(lightness: 80, cct: 3000)
                ]
            case .rest:
                self.title = "templates_rest".localizedString
                self.imageId = 10
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 2700)
                ]
                //******* 工业 ******/
            case .prepareWork: // 准备上班
                self.title = "templates_prepare_work".localizedString
                self.imageId = 23
                self.parameters = [
                    SceneParameter(lightness: 80, cct: 5000)
                ]
            case .industryWork: // 上班
                self.title = "templates_go_to_work".localizedString
                self.imageId = 25
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5500)
                ]
            case .industryRest:
                self.title = "templates_industry_break".localizedString
                self.imageId = 10
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000)
                ]
            case .industryOffWork: // 下班（工业）
                self.title = "templates_off_work".localizedString
                self.imageId = 24
                self.parameters = [
                    SceneParameter(lightness: 0, cct: 5000)
                ]
                //******* 超市 ******/
            case .prepareBusiness:
                self.title = "templates_prepare_business".localizedString
                self.imageId = 23
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000),
                    SceneParameter(lightness: 50, cct: 5000),
                    SceneParameter(lightness: 80, cct: 5000)
                ]
            case .regular:
                self.title = "templates_regular".localizedString
                self.imageId = 27
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000)
                ]
            case .peakTraffic:
                self.title = "templates_peak_traffic".localizedString
                self.imageId = 29
                self.parameters = [
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            case .lowTraffic:
                self.title = "templates_low_traffic".localizedString
                self.imageId = 30
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000),
                    SceneParameter(lightness: 50, cct: 5000),
                    SceneParameter(lightness: 100, cct: 5000)
                ]
            case .close:
                self.title = "templates_close".localizedString
                self.imageId = 28
                self.parameters = [
                    SceneParameter(lightness: 10, cct: 5000),
                    SceneParameter(lightness: 50, cct: 5000),
                    SceneParameter(lightness: 80, cct: 5000)
                ]
            }
        }
        
    }
    
}

