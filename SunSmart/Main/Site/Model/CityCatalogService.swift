import Foundation

extension CityCatalogStore {
    static let shared: CityCatalogStore = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CityCatalog/v1", isDirectory: true)
        func cache(_ code: String) -> CountryRegionCatalogCache {
            CountryRegionCatalogCache(url: root.appendingPathComponent(code).appendingPathExtension("json"))
        }
        return CityCatalogStore(readCache: { try cache($0).read() }, writeCache: { try cache($0).write($1) }) { code, completion in
            let region = UserData.currentServerRegion
            #if DEBUG
            print("[CityCatalog] Starting a city catalog request; country=\(code), region=\(region.rawValue).")
            #endif
            Task { @MainActor in
                let result = await NetworkRequest.shared.request(.siteCities(countryCode: code, region: region), maximumDuration: 10)
                completion(result.mapError { $0 as Error })
            }
        }
    }()
}
