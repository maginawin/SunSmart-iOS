import Foundation

/// All mutations run on the main thread and start from the persisted Space.
/// Transport results share this boundary with edits so stale pages cannot replace newer state.
enum HDBConfigurationStore {
    /// Provisioning resets subscriptions even when it reuses the primary address.
    /// Replay nonempty targets; a known reset already satisfies an empty Zone target.
    static func restoreDevice(space: SpaceData, nodeUuid: UUID, nodeAddress: UInt16, mac: String?,
                              modelConfiguration: HDBDeviceConfiguration? = nil, subscriptionsWereReset: Bool = false) throws {
        guard try load(space: space).devices.contains(where: { $0.nodeUuid == nodeUuid }) else { return }
        let mac = try HDBDeviceConfiguration.normalizedMAC(mac)
        try update(space: space) { config in
            guard let index = config.devices.firstIndex(where: { $0.nodeUuid == nodeUuid }) else { return }
            guard config.devices[index].nodeAddress == nodeAddress || modelConfiguration != nil else { throw HDBConfigurationError.invalidData }
            let modelsChanged = modelConfiguration.map { !config.devices[index].hasSameModels(as: $0) } ?? false
            if let modelConfiguration {
                guard modelConfiguration.nodeUuid == nodeUuid, modelConfiguration.nodeAddress == nodeAddress else { throw HDBConfigurationError.invalidData }
                config.devices[index].copyModels(from: modelConfiguration)
            }
            config.devices[index].nodeAddress = nodeAddress
            config.devices[index].mac = mac
            try config.devices[index].refreshSensorPublication()
            config.devices[index].lightingConfiguration?.mark(fields: ["dimIntensity", "brightIntensity", "rampUpTime", "rampDownTime", "holdTime"], status: .pending)
            config.devices[index].lightingConfiguration?.merge(.init(lightingControl: .auto), status: .pending)
            if !config.devices[index].lightingZones.isEmpty || (modelsChanged && !subscriptionsWereReset) {
                config.devices[index].lightingZonesStatus = .pending
            } else if subscriptionsWereReset {
                config.devices[index].lightingZonesStatus = .synced
            }
            // A signature refresh is not a reset. Preserve both confirmed empty
            // targets and pending user-requested clears across initialization retries.
        }
    }

    static func revision(space: SpaceData) throws -> Int64 {
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshNetworkId == space.meshNetworkId, !latest.hdbLoadFailed else { throw HDBConfigurationError.unavailable }
        return latest.lastUpdate
    }

    static func load(space: SpaceData) throws -> HDBConfiguration {
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshNetworkId == space.meshNetworkId, !latest.hdbLoadFailed else { throw HDBConfigurationError.unavailable }
        let config = latest.hdb ?? HDBConfiguration()
        try HDBLightingZonePolicy.validate(config)
        return config
    }

    static func update(space: SpaceData, refreshCounts: Bool = false, _ mutate: (inout HDBConfiguration) throws -> Void) throws {
        precondition(Thread.isMainThread)
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshNetworkId == space.meshNetworkId, !latest.hdbLoadFailed else { throw HDBConfigurationError.unavailable }
        guard latest.canEditing, space.groupOperates.contains(.edit), SpaceMembershipCoordinator.allowsConfiguration(latest),
              !SpaceConfigurationSafety.isBlocked(latest) else { throw HDBConfigurationError.permissionDenied }
        var config = latest.hdb ?? HDBConfiguration()
        try mutate(&config)
        try HDBLightingZonePolicy.validate(config)
        latest.hdb = config
        if refreshCounts { latest.refreshSummaryCountsFromSpaceMesh() }
        latest.lastUpdate = max(Int64(Date().timeIntervalSince1970), latest.lastUpdate + 1,
                                (latest.lastUploadCloudTimestamp ?? 0) + 1)
        guard latest.save() else { throw HDBConfigurationError.persistenceFailed }
        // Keep transient UI permissions/OTA state owned by the active Space object.
        space.hdb = latest.hdb; space.hdbPersistenceBaseline = latest.hdbPersistenceBaseline
        space.hdbLoadFailed = latest.hdbLoadFailed; space.lastUpdate = latest.lastUpdate
        if refreshCounts {
            space.deviceCount = latest.deviceCount; space.luminairesCount = latest.luminairesCount
            space.groupCount = latest.groupCount; space.sceneCount = latest.sceneCount
            space.scheheduleCount = latest.scheheduleCount; space.switchesCount = latest.switchesCount
        }
        if let site = SiteData.load(siteId: space.siteId) {
            site.spaces = SpaceData.load(siteId: space.siteId)
            space.enqueueSpaceSync(site: site, level: .promptly)
        }
    }
}
