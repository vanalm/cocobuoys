//
//  HomeSummary.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation

struct HomeSummary: Equatable {
    let waveStationName: String?
    let waveHeightFeet: Double?
    let wavePeriodSeconds: Double?
    let waveDirectionCardinal: String?
    
    let windStationName: String?
    let windSpeedKnots: Double?
    let windDirectionCardinal: String?
    let windGustKnots: Double?
}
