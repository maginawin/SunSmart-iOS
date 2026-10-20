import Foundation

// check_hdb_integration.py inserts the mapped SDK's actual isKeybindComplete getter.
// Radio, composition metadata and publication policy remain explicit test boundaries.
extension MeshLibManager {
    static var testPublishModelIDs: [UInt16] = []
    var publishModelIDs: [UInt16] { Self.testPublishModelIDs }
    var publishModeloOnly: Bool { true }
}
extension MeshNetworkManager.Key {
    var index: UInt16 { 0 }
    var isPrimary: Bool { false }
}
extension ApplicationKey: Equatable {
    var boundNetworkKeyIndex: UInt16 { boundNetworkKey.index }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.index == rhs.index }
}
extension Group {
    static var subElementBroadcastGroup: Group { Group(0xFEFD) }
}
extension Element {
    var isPrimary: Bool {
        MeshNetworkManager.instance.meshNetwork?.nodes.contains { $0.elements.first === self } ?? false
    }
}
extension Model {
    var bind: [UInt16] { boundApplicationKeys.map(\.index) }
    func isSubscribed(to group: Group) -> Bool { subscriptions.contains { $0.address == group.address } }
}
extension Node {
    enum RequiredFunctionType { case mainNetwork }
    var isInitialize: Bool { true }
    var parentNetworkKey: MeshNetworkManager.Key? { network?.networkKeys.first }
    var applicationKeys: [ApplicationKey] { network?.applicationKeys ?? [] }
    var requiredFunctionTypes: [RequiredFunctionType] { [] }
    var supportModels: [Model] { elements.flatMap(\.models) }
    var sensorModels: [Model] { supportModels.filter { $0.modelIdentifier == 0x1100 } }
    var firmwareUpdateServerModel: Model? { nil }
    var firmwareID: Data? { nil }
    var sunricherVendorModel: Model? { supportModels.first { $0.companyIdentifier == 0x0A78 } }
    var compositionHash: Data? { Data([1]) }
}

enum HDBSubelementFixture {
    // The log's 0002/0003/0004 topology, including the LC shared table and
    // a cross-element extension that clears across elements but adds per element.
    static func configure(_ node: Node, sensor: Bool = true) {
        let primary = Element(), temperature = Element(), lc = Element()
        node.primaryUnicastAddress = 2
        primary.unicastAddress = 2; temperature.unicastAddress = 3; lc.unicastAddress = 4
        primary.models = [Model(0x1000), Model(0x1300), Model(1, company: 0x0A78), Model(0x1002)]
        temperature.models = [Model(0x1306)]
        temperature.models[0].subscriptions = [Group(0xFEFD)]
        lc.models = [Model(0x1000), Model(0x130F), Model(0x1310)]
        let extensionChain = [primary.models[0], primary.models[1], primary.models[3]] + lc.models
        for model in extensionChain { model.relatedModels = extensionChain.filter { $0 !== model } }
        for model in lc.models { model.subscriptions = [Group(0xFEFD)] }
        node.elements = [primary, temperature, lc]
        if sensor {
            let presence = Model(0x1100), ambient = Model(0x1100)
            primary.models.append(presence); temperature.models.append(ambient)
            node.presenceDetectedSensorModel = presence; node.ambientLightSensorModel = ambient
            node.sensorModelTypes = [presence: .init(id: 0x004D), ambient: .init(id: 0x004E)]
        }
        for element in node.elements { element.models.forEach { $0.parentElement = element } }
    }
}
