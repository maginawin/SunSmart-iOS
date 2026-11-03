import Foundation

extension CountryRegionCatalogStore {
    /// Shared across accounts/regions: the server contract supplies the same public list everywhere.
    static let shared: CountryRegionCatalogStore = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cache = CountryRegionCatalogCache(url: root.appendingPathComponent("CountryCatalog/countries-v1.json"))
        return CountryRegionCatalogStore(readCache: cache.read, writeCache: cache.write) { completion in
            let region = UserData.currentServerRegion
            #if DEBUG
            print("[CountryCatalog] Starting a country catalog request; region=\(region.rawValue).")
            #endif
            Task { @MainActor in
                let result = await NetworkRequest.shared.request(.siteCountries(region: region), maximumDuration: 10)
                completion(result.mapError { $0 as Error })
            }
        }
    }()
}
