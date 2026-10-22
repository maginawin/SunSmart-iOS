"""Share the production factory and mapped SDK relationships between recovery probes."""
import re


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def recovery_mesh_source(root):
    sdk = root / '.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision'
    models = (sdk / 'Mesh API/Models.swift').read_text()
    relations = section(models, '    var relatedModels:', '    /// Returns whether')
    relations += section(models, '    func extendsDirectly(', '\n    }') + '\n    }\n'
    factory = section((root / 'SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift').read_text(),
                      '    static func deviceConfiguration(', '    /// Check one already loaded')
    for old, new in [('Node', 'RecoveryMeshNode'), ('Element', 'RecoveryMeshElement'), ('Model', 'RecoveryMeshModel')]:
        relations = re.sub(r'\b' + old + r'\b', new, relations)
        factory = re.sub(r'\b' + old + r'\b', new, factory)
    constants = '\n'.join(re.findall(r'^    static let \w+: UInt16 = 0x[0-9a-fA-F]+', models, re.M))
    return (root / 'Tests/HDB/HDBRecoveryMeshBoundaries.swift').read_text().replace(
        '// SDK_MODEL_RELATIONSHIPS', relations).replace('// APP_DEVICE_FACTORY', factory) + '\nextension UInt16 {\n' + constants + '\n}\n'
