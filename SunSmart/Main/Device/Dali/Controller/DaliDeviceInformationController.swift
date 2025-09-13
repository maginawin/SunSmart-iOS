//
//  DaliDeviceInformationController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/13.
//

import UIKit

class DaliDeviceInformationController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }


}

extension DaliDeviceInformationController {
    
    enum InfoType {
//        var title: String {
//            switch self {
//            case .daliAddress:
//                return 
//            case .daliGroup:
//                <#code#>
//            case .daliStatus:
//                <#code#>
//            case .gtin:
//                <#code#>
//            case .serial:
//                <#code#>
//            case .deviceManufacurer:
//                <#code#>
//            case .deviceModel:
//                <#code#>
//            case .deviceType:
//                <#code#>
//            case .fwVersion:
//                <#code#>
//            case .hwVersion:
//                <#code#>
//            case .manufacureTime:
//                <#code#>
//            case .energyLastUpdate:
//                <#code#>
//            case .activeEnergy:
//                <#code#>
//            case .activePower:
//                <#code#>
//            case .apparentEnergy:
//                <#code#>
//            case .apparentPower:
//                <#code#>
//            case .loadSideActiveEnergy:
//                <#code#>
//            case .loadSideActivePower:
//                <#code#>
//            case .systemStarts:
//                <#code#>
//            case .operatingTime:
//                <#code#>
//            case .lampOnTime:
//                <#code#>
//            case .operatingTemperature:
//                <#code#>
//            case .powerFactorPercentage:
//                <#code#>
//            case .outputCurrentPercentage:
//                <#code#>
//            case .outputCurrent:
//                <#code#>
//            case .outputVoltage:
//                <#code#>
//            case .lampStarts:
//                <#code#>
//            case .lampTemperature:
//                <#code#>
//            case .gearFailureCounter:
//                <#code#>
//            case .gearStatus:
//                <#code#>
//            case .lampFailureCounter:
//                <#code#>
//            case .lampStatus:
//                <#code#>
//            case .inputVoltage:
//                <#code#>
//            case .mb1OEMExtensions:
//                <#code#>
//            case .luminaireManufacturer:
//                <#code#>
//            case .luminaireGTIN:
//                <#code#>
//            case .luminaireSerial:
//                <#code#>
//            case .nominaliInputPower_w:
//                <#code#>
//            case .nominalLightOutput_lm:
//                <#code#>
//            case .minimumDimPower_w:
//                <#code#>
//            case .cri:
//                <#code#>
//            case .cct:
//                <#code#>
//            case .scanDali:
//                <#code#>
//            case .deviceDiagnostics:
//                <#code#>
//            case .cg_overallFailure:
//                <#code#>
//            case .cg_overallFailureN:
//                <#code#>
//            case .cg_underVoltage:
//                <#code#>
//            case .cg_underVoltageN:
//                <#code#>
//            case .cg_overVoltage:
//                <#code#>
//            case .cg_overVoltageN:
//                <#code#>
//            case .cg_outputLimitation:
//                <#code#>
//            case .cg_outputLimitationN:
//                <#code#>
//            case .cg_thermalDerating:
//                <#code#>
//            case .cg_thermalDeratingN:
//                <#code#>
//            case .cg_thermalShutdown:
//                <#code#>
//            case .cg_thermalShutdownN:
//                <#code#>
//            case .lightSourceDiagnostics:
//                <#code#>
//            case .ls_overallFailure:
//                <#code#>
//            case .ls_overallFailureN:
//                <#code#>
//            case .ls_ShortCircuit:
//                <#code#>
//            case .ls_ShortCircuitN:
//                <#code#>
//            case .ls_OpenCircuit:
//                <#code#>
//            case .ls_OpenCircuitN:
//                <#code#>
//            case .luminaireMaintenance:
//                <#code#>
//            case .ratedMedianLife:
//                <#code#>
//            case .internalReferenceTemperature:
//                <#code#>
//            case .ratedMedianStarts:
//                <#code#>
//            }
//        }
        
        
        case daliAddress
        case daliGroup
        case daliStatus
        case gtin
        case serial
        case deviceManufacurer
        case deviceModel
        case deviceType
        case fwVersion
        case hwVersion
        case manufacureTime
        case energyLastUpdate
        case activeEnergy
        case activePower
        case apparentEnergy
        case apparentPower
        case loadSideActiveEnergy
        case loadSideActivePower
        case systemStarts
        case operatingTime
        case lampOnTime
        case operatingTemperature
        case powerFactorPercentage
        case outputCurrentPercentage
        case outputCurrent
        case outputVoltage
        case lampStarts
        case lampTemperature
        case gearFailureCounter
        case gearStatus
        case lampFailureCounter
        case lampStatus
        case inputVoltage
        case mb1OEMExtensions
        case luminaireManufacturer
        case luminaireGTIN
        case luminaireSerial
        case nominaliInputPower_w
        case nominalLightOutput_lm
        case minimumDimPower_w
        case cri
        case cct
        case scanDali
        case deviceDiagnostics
        case cg_overallFailure
        case cg_overallFailureN
        case cg_underVoltage
        case cg_underVoltageN
        case cg_overVoltage
        case cg_overVoltageN
        case cg_outputLimitation
        case cg_outputLimitationN
        case cg_thermalDerating
        case cg_thermalDeratingN
        case cg_thermalShutdown
        case cg_thermalShutdownN
        case lightSourceDiagnostics
        case ls_overallFailure
        case ls_overallFailureN
        case ls_ShortCircuit
        case ls_ShortCircuitN
        case ls_OpenCircuit
        case ls_OpenCircuitN
        case luminaireMaintenance
        case ratedMedianLife
        case internalReferenceTemperature
        case ratedMedianStarts
    }
    
}
