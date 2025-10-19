//
//  HomeLocationStore.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import CoreLocation

protocol HomeLocationStoring {
    func load() -> CLLocationCoordinate2D?
    func save(_ coordinate: CLLocationCoordinate2D)
    func clear()
}

struct StoredHomeLocation: Codable {
    let latitude: Double
    let longitude: Double
}

final class HomeLocationStore: HomeLocationStoring {
    private let defaults: UserDefaults
    private let key = "homeLocation"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func load() -> CLLocationCoordinate2D? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredHomeLocation.self, from: data) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: stored.latitude, longitude: stored.longitude)
    }
    
    func save(_ coordinate: CLLocationCoordinate2D) {
        let stored = StoredHomeLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }
    
    func clear() {
        defaults.removeObject(forKey: key)
    }
}
