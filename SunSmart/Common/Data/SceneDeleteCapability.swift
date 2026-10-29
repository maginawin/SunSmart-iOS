import Foundation

enum SceneDeleteCapability {
    static func needsRemoval(observed: Set<UInt16>?, number: UInt16, hasCachedData: Bool) -> Bool {
        observed?.contains(number) != false || hasCachedData
    }

    static func isSupported<Model>(sceneSetupModel: Model?) -> Bool {
        sceneSetupModel != nil
    }
}
