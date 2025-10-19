//
//  MarineStation.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import CoreLocation

/// Base class for any marine observation station that we render on the map.
class MarineStation: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let lastUpdated: Date?
    
    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.lastUpdated = lastUpdated
    }
}
