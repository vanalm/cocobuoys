//
//  StationAnnotation.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import MapKit

enum StationAnnotationKind {
    case wave(style: BuoyMarkerStyle)
    case wind(style: WindMarkerStyle)
}

final class StationAnnotation: NSObject, MKAnnotation {
    let station: MarineStation
    let kind: StationAnnotationKind
    let identifier: String
    
    init(station: MarineStation, kind: StationAnnotationKind) {
        self.station = station
        self.kind = kind
        switch kind {
        case .wave:
            identifier = "\(station.id)-wave"
        case .wind:
            identifier = "\(station.id)-wind"
        }
    }
    
    var buoy: Buoy? {
        station as? Buoy
    }
    
    var coordinate: CLLocationCoordinate2D {
        station.coordinate
    }
    
    var title: String? {
        station.name
    }
}
