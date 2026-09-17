#!/usr/bin/env python3
"""Assemble the production read-only topology reader with real SQLite/SDK boundaries."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(path):
    return (ROOT / path).read_text()
def block(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]
def source():
    db = read('SunSmart/Common/Data/Database.swift')
    snapshot = read('SunSmart/Common/Data/NodeSyncTopologySnapshot.swift')
    planner = read('SunSmart/Main/Group/Model/GroupProximityLightingData.swift')
    site = read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyReader.swift')
    parts = [
        read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift'),
        read('SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'),
        block(read('SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyPolicy.swift'), 'enum SiteTriggerZoneTopologyPolicy'),
        block(snapshot, 'struct NodeSyncTopologySnapshot'),
        block(snapshot, 'struct NodeSyncPreparedTopology'),
        'enum NodeSyncTopologyCapture {\n' + block(snapshot, 'static func isMembershipGroup(') + '\n}',
        'enum ProximityLightingTopologyPlanner {\n' + block(planner, 'static func makeSpaceZoneSnapshots(') + '\n}',
        'enum SiteTriggerZoneTopologyReader {\n' + block(site, 'enum LocalTargetSnapshot') + '\n}',
        'enum SiteData {\n' + block(db[db.index('extension SiteData {'):], 'struct ExpressionKey') + '\n' + block(read('SunSmart/Common/Data/SiteData.swift'), 'enum State: Int') + '\n}',
        'enum SpaceData {\n' + block(db[db.index('extension SpaceData {'):], 'struct ExpressionKey') + '\n' + block(read('SunSmart/Common/Data/SpaceData.swift'), 'enum State: Int') + '\n}',
        block(read('SunSmart/Common/Data/NodeSyncTopologyStorage.swift'), 'enum NodeSyncTopologyStorage'),
        read('Tests/Group/NodeSyncTopologyStorageTests.swift'),
    ]
    aliases = '\n'.join('typealias '+name+' = NordicSigMeshSDK.'+name for name in ['Node','Model','Element','Group','MeshAddress','MeshNetwork','NetworkKey','ApplicationKey','Provisioner','MeshDataManager'])
    return 'import Foundation\nimport SQLite\nimport CryptoKit\nimport NordicSigMeshSDK\nimport struct SQLite.Expression\nprivate extension Array { var only: Element? { count == 1 ? self[0] : nil } }\nenum SyncTopologyStorageTests {\n'+aliases+'\n'+'\n'.join(parts).replace('import Foundation','')+'\n}\n'
