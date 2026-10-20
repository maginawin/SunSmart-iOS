import Foundation

// SDK cache/database boundaries; the production HDB task owns ACK validation and persistence.
extension TestPublish {
    init(to address: MeshAddress, using key: ApplicationKey, usingFriendshipMaterial: Bool,
         ttl: UInt8, period: Timing, retransmit: Retransmit) {
        self.init(publicationAddress: address, index: key.index, ttl: ttl, period: period, retransmit: retransmit)
    }
}
struct ConfigModelPublicationSet: MeshMessage {
    let model: Model, publication: Publish
    var parameters: Data {
        let element = model.parentElement!.unicastAddress, address = publication.publicationAddress.address
        return Data([UInt8(element & 255), UInt8(element >> 8), UInt8(address & 255), UInt8(address >> 8),
            UInt8(publication.index & 255), UInt8(publication.index >> 8), publication.ttl, publication.period == .disabled ? 0 : 1,
            publication.retransmit.steps << 3 | publication.retransmit.count,
            UInt8(model.modelIdentifier & 255), UInt8(model.modelIdentifier >> 8)])
    }
    init?(_ publication: Publish, to model: Model) { self.publication = publication; self.model = model }
    init?(disablePublicationFor model: Model) { self.init(Publish(publicationAddress: MeshAddress(0)), to: model) }
}
struct ConfigModelPublicationStatus: MeshMessage {
    let parameters: Data, isSuccess: Bool
    init(_ request: ConfigModelPublicationSet, success: Bool) { parameters = Data([success ? 0 : 1]) + request.parameters; isSuccess = success }
}
enum TaskPersistenceBoundary { static var failNodeSave: Bool { get { Node.failSave } set { Node.failSave = newValue } } }
extension Node {
    func applyMessageHandle(_ handle: MeshMessageHandle, isSuccess: Bool) {
        if let set = handle.message as? ConfigModelPublicationSet {
            set.model.publish = set.publication.publicationAddress.address == 0 ? nil : set.publication
        }
    }
}
