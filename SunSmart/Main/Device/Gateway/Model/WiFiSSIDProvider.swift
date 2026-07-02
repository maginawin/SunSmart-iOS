//
//  WiFiSSIDProvider.swift
//  SunSmart
//

import CoreLocation
import Foundation
import NetworkExtension

final class WiFiSSIDProvider: NSObject {
    static let shared = WiFiSSIDProvider()

    private let locationManager = CLLocationManager()
    private var pendingCompletions: [(String) -> Void] = []

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func fetchCurrentSSID(completion: @escaping (String) -> Void) {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            fetchSSIDWithoutPermissionRequest(completion: completion)
        case .notDetermined:
            pendingCompletions.append(completion)
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            completion("")
        @unknown default:
            completion("")
        }
    }

    private func fetchSSIDWithoutPermissionRequest(completion: @escaping (String) -> Void) {
        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { network in
                DispatchQueue.main.async {
                    completion(network?.ssid ?? "")
                }
            }
        } else {
            completion("")
        }
    }
}

extension WiFiSSIDProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        guard !completions.isEmpty else { return }

        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            completions.forEach { $0("") }
            return
        }

        fetchSSIDWithoutPermissionRequest { ssid in
            completions.forEach { $0(ssid) }
        }
    }
}
