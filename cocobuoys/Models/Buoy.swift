//
//  Buoy.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import CoreLocation
import SwiftUI

struct SwellMetrics {
    var heightMeters: Double?
    var periodSeconds: Double?
    var directionDegrees: Double?
    
    static let empty = SwellMetrics(heightMeters: nil, periodSeconds: nil, directionDegrees: nil)
}

struct BuoyObservation: Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let heightFeet: Double?
    let periodSeconds: Double?
    let directionCardinal: String?
    let waterTemperatureFahrenheit: Double?
    let windSpeedKnots: Double?
    let windGustKnots: Double?
    let directionDegrees: Double?
    let windDirectionCardinal: String?
    let windDirectionDegrees: Double?
    let airTemperatureFahrenheit: Double?
    let pressureMillibars: Double?
    let pressureTendencyMillibars: Double?
    let salinityPSU: Double?
    let tideFeet: Double?
    let visibilityNauticalMiles: Double?
    
    init(
        id: String,
        timestamp: Date,
        heightFeet: Double? = nil,
        periodSeconds: Double? = nil,
        directionCardinal: String? = nil,
        waterTemperatureFahrenheit: Double? = nil,
        windSpeedKnots: Double? = nil,
        windGustKnots: Double? = nil,
        directionDegrees: Double? = nil,
        windDirectionCardinal: String? = nil,
        windDirectionDegrees: Double? = nil,
        airTemperatureFahrenheit: Double? = nil,
        pressureMillibars: Double? = nil,
        pressureTendencyMillibars: Double? = nil,
        salinityPSU: Double? = nil,
        tideFeet: Double? = nil,
        visibilityNauticalMiles: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.heightFeet = heightFeet
        self.periodSeconds = periodSeconds
        self.directionCardinal = directionCardinal
        self.waterTemperatureFahrenheit = waterTemperatureFahrenheit
        self.windSpeedKnots = windSpeedKnots
        self.windGustKnots = windGustKnots
        self.directionDegrees = directionDegrees
        self.windDirectionCardinal = windDirectionCardinal
        self.windDirectionDegrees = windDirectionDegrees
        self.airTemperatureFahrenheit = airTemperatureFahrenheit
        self.pressureMillibars = pressureMillibars
        self.pressureTendencyMillibars = pressureTendencyMillibars
        self.salinityPSU = salinityPSU
        self.tideFeet = tideFeet
        self.visibilityNauticalMiles = visibilityNauticalMiles
    }
    
    var heightMeters: Double? {
        heightFeet.map { $0 * 0.3048 }
    }
}

/// Representation for NOAA NDBC buoys and their swell data.
class Buoy: MarineStation {
    let observations: [BuoyObservation]
    
    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        observations: [BuoyObservation],
        lastUpdated: Date? = nil
    ) {
        self.observations = observations.sorted { $0.timestamp < $1.timestamp }
        super.init(id: id, name: name, coordinate: coordinate, lastUpdated: lastUpdated)
    }
    
    var latestObservation: BuoyObservation? {
        observations.last
    }
    
    var swell: SwellMetrics {
        guard let latestObservation else { return .empty }
        return SwellMetrics(
            heightMeters: latestObservation.heightMeters,
            periodSeconds: latestObservation.periodSeconds,
            directionDegrees: latestObservation.directionDegrees
        )
    }
    
    var hasWaveData: Bool {
        latestObservation?.heightFeet != nil || latestObservation?.periodSeconds != nil || latestObservation?.directionDegrees != nil
    }
    
    var hasWindData: Bool {
        latestWindObservation != nil
    }
    
    var latestWindObservation: BuoyObservation? {
        observations.last(where: { $0.windSpeedKnots != nil || $0.windDirectionDegrees != nil })
    }
}

/// Styling information we pass to the map annotation layer.
struct BuoyMarkerStyle: Hashable {
    var color: Color
    var opacity: Double
    var size: CGFloat
    var direction: Double
}

struct WindMarkerStyle: Hashable {
    var speedKnots: Double?
    var gustKnots: Double?
    var direction: Double?
    var color: Color
    
    static func color(for speed: Double?) -> Color {
        guard let speed else { return .gray }
        switch speed {
        case ..<10:
            return .green
        case 10..<20:
            return .yellow
        default:
            return .red
        }
    }
}
