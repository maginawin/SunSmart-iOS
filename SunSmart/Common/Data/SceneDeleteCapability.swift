import Foundation

enum SceneDeleteCapability {
    static func isSupported<Model>(sceneSetupModel: Model?) -> Bool {
        sceneSetupModel != nil
    }
}
