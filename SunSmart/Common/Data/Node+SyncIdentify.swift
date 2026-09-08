import Foundation
import NordicSigMeshSDK

extension Node {

    /// 发送配置完成闪烁消息
    func sendHandleCompleteIdentify(deviceBlinkMode: DeviceBlinkMode) {

        guard let vendorModel = sunricherVendorModel, capabilities.contains(.setupBehavior) else { return }

        switch deviceBlinkMode {
        case .none:
            break
        case .breathing:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: vendorModel)
        case .fast:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .flash(count: 1))), model: vendorModel)
        }
    }
}
