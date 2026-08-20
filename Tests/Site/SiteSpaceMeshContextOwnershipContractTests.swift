import Foundation

@main
struct SiteSpaceMeshContextOwnershipContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError(
                "Expected SiteViewController.swift, SpaceViewController.swift, " +
                "and ImportData.swift paths"
            )
        }

        let siteSource = try read(CommandLine.arguments[1])
        let spaceSource = try read(CommandLine.arguments[2])
        let importSource = try read(CommandLine.arguments[3])

        let siteLoad = section(
            in: siteSource,
            from: "private func performSiteLoad(",
            to: "/// 获取space数据"
        )
        require(
            !siteLoad.contains("setMeshNetworkConnected("),
            "A completed Site request must not replace the active global Mesh context"
        )

        let siteDidAppear = section(
            in: siteSource,
            from: "override func viewDidAppear(_ animated: Bool)",
            to: "override func viewDidDisappear(_ animated: Bool)"
        )
        require(
            siteDidAppear.contains(
                "setMeshNetworkConnected(meshUUID: self.site.meshUUID, " +
                "subNetworkId: self.site.meshNetworkId, connected: false)"
            ),
            "The visible Site lifecycle must remain the owner of Primary Mesh activation"
        )
        require(
            siteDidAppear.contains("self.setupData()"),
            "Site data must refresh after the visible lifecycle activates Primary Mesh"
        )

        require(
            siteSource.contains("private func sitePrimaryMeshNetwork() -> MeshNetwork?") &&
                siteSource.contains("model.resolveNode(in: meshNetwork)"),
            "Gateway rendering must resolve nodes from an explicit Site Primary Mesh"
        )

        let spaceConnection = section(
            in: spaceSource,
            from: "private func setNetworkConnected()",
            to: "// MARK: - Request"
        )
        require(
            spaceConnection.contains(
                "setMeshNetworkConnected(meshUUID: self.space.meshUUID, " +
                "subNetworkId: self.space.meshNetworkId)"
            ),
            "Space entry must remain the owner of its subnetwork activation"
        )

        let siteImport = section(
            in: importSource,
            from: "func update(siteJsonData:",
            to: "/// 添加site内用户资源"
        )
        require(
            siteImport.contains(
                "currentManager.meshNetwork?.uuid.uuidString == self.meshUUID"
            ) &&
                siteImport.contains(
                    "currentManager.currentNetworkKey.networkId.hex == self.meshNetworkId"
                ) &&
                siteImport.contains("currentManager.currentNetworkKey.isPrimary"),
            "Site import may reuse the global Manager only for the exact Primary network"
        )
        require(
            siteImport.contains("subnetworkId: self.meshNetworkId") &&
                siteImport.contains("allData: false"),
            "Site import must explicitly load its Primary network when global context differs"
        )

        let spaceImport = section(
            in: importSource,
            from: "func update(spaceJsonData:",
            to: "extension Node"
        )
        require(
            spaceImport.contains(
                "meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString"
            ) &&
                spaceImport.contains(
                    "MeshNetworkManager.instance.currentNetworkKey.networkId.hex == " +
                    "self.meshNetworkId"
                ) &&
                spaceImport.contains("MeshNetworkManager.instance.schedules = schedules"),
            "Space schedules may update the global Manager only for the exact subnetwork"
        )

        print("SiteSpaceMeshContextOwnershipContractTests passed")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let startRange = source.range(of: startMarker) else {
            fatalError("Missing source marker: \(startMarker)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: endMarker) else {
            fatalError("Missing source marker: \(endMarker)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
