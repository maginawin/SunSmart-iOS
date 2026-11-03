import Foundation

// The pre-existing Scene suites exercise store/command/lifecycle behavior with
// no cascade references. Real cascade discovery, messages and receipts execute
// production SceneDeletionCascade.swift in check_scene_deletion_cascade.py.
enum SceneDeletionCascade {
    static func hasPending(_ info: SceneInfo) -> Bool {
        info.configuration?.deletionReferences?.pending.isEmpty == false
    }

    #if SCENE_CASCADE_STORE_BOUNDARY
    struct Preparation {
        var references = SceneDeletionReferences()
        func persist() throws {}
        func install() {}
    }
    static func prepare(scene: Scene, snapshot: SceneTargetSnapshot, additionalNodes: [Node] = []) throws -> Preparation {
        precondition(SceneConfigurationStore.deletionReferenceNames(number: scene.number).isEmpty,
                     "Reference cleanup must use the production cascade suite")
        return .init()
    }
    // Legacy suites deliberately exclude Scheduler cleanup; the production recovery helper is covered by the cascade suite.
    static func restoringSchedulerCoverage(_ configuration: SceneConfiguration, nodes: [Node]) throws -> SceneConfiguration { configuration }
    static func canFinish(info: SceneInfo) -> Bool {
        !hasPending(info) && SceneConfigurationStore.deletionReferenceNames(number: info.sceneId).isEmpty
    }
    static func finalizeReferences(info: SceneInfo, scope: SceneScope) throws {}
    static func refreshSchedules(scope: SceneScope) {}
    #endif

    #if SCENE_CASCADE_TASK_BOUNDARY
    static func appendTasks(scene: Scene, to section: SyncDevicesSectionModel) -> [SyncDeviceStepModel] {
        precondition(!hasPending(scene.info), "Reference tasks must use the production cascade suite")
        return []
    }
    #endif
}
