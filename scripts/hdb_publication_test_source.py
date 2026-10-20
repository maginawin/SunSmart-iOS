"""Use the shared App policy and mapped SDK retransmit value in HDB fixtures."""


def swift_block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def with_publication_policy(source, root):
    policy = (root / "SunSmart/Common/Data/Node+SyncData.swift").read_text()
    sdk = root / ".local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/Publish.swift"
    retransmit = swift_block(sdk.read_text(), "    public struct Retransmit:").replace("public ", "")
    return source.replace("// Inject SDK Retransmit here.", retransmit).replace(
        "// Inject SensorPublicationPolicy here.", swift_block(policy, "enum SensorPublicationPolicy {"))
