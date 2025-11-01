//
//  HomeSummary.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation

struct HomeSummary: Equatable {
    struct WaveSample: Identifiable, Equatable {
        let timestamp: Date
        let heightFeet: Double?
        let periodSeconds: Double?
        
        var id: Date { timestamp }
    }
    
    struct WindSample: Identifiable, Equatable {
        let timestamp: Date
        let speedKnots: Double?
        let gustKnots: Double?
        
        var id: Date { timestamp }
    }
    
    let waveStationName: String?
    let waveStationId: String?
    let waveHeightFeet: Double?
    let wavePeriodSeconds: Double?
    let waveDirectionCardinal: String?
    let waveUpdatedAt: Date?
    let waveSamples: [WaveSample]
    
    let windStationName: String?
    let windStationId: String?
    let windSpeedKnots: Double?
    let windDirectionCardinal: String?
    let windGustKnots: Double?
    let windUpdatedAt: Date?
    let windSamples: [WindSample]
}
