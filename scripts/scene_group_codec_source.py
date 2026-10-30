"""Actual SDK codecs for offline Scene payload tests; no copied field schema."""
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

def scene_group_codec_source(root):
    sdk = root / '.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK'
    return ('import Foundation\npublic typealias SceneNumber = UInt16\n' +
        (sdk / 'MeshLib/Scene/SceneExecuteData.swift').read_text() + '\n' +
        block((sdk / 'MeshLib/Node/Node+Propertys.swift').read_text(), 'public class LightLCProperty:') + '\n' +
        block((sdk / 'MeshLib/Message/Vendor/SunricherVendorStatus.swift').read_text(), 'public enum ManualOverrideState:'))
