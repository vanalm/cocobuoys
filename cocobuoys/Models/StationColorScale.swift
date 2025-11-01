//
//  StationColorScale.swift
//  cocobuoys
//
//  Created by Codex on 10/23/25.
//

import SwiftUI

enum StationColorScale {
    private struct RGB {
        let r: Double
        let g: Double
        let b: Double
        
        var color: Color { Color(red: r, green: g, blue: b) }
    }
    
    private static let waveHeightPalette: [RGB] = [
        .init(r: 0.078, g: 0.200, b: 0.475), // deep blue
        .init(r: 0.000, g: 0.482, b: 0.643), // teal
        .init(r: 0.305, g: 0.733, b: 0.482), // seafoam
        .init(r: 0.937, g: 0.902, b: 0.188), // golden yellow
        .init(r: 0.976, g: 0.647, b: 0.149), // orange
        .init(r: 0.890, g: 0.141, b: 0.114)  // crimson
    ]
    
    private static let wavePeriodPalette: [RGB] = [
        .init(r: 0.464, g: 0.102, b: 0.667), // violet
        .init(r: 0.239, g: 0.188, b: 0.745), // indigo
        .init(r: 0.000, g: 0.451, b: 0.851), // sky blue
        .init(r: 0.059, g: 0.702, b: 0.729), // cyan
        .init(r: 0.478, g: 0.780, b: 0.251), // lime
        .init(r: 0.965, g: 0.745, b: 0.078), // amber
        .init(r: 0.925, g: 0.271, b: 0.106)  // orange-red
    ]
    
    private static let windSpeedPalette: [RGB] = [
        .init(r: 0.078, g: 0.318, b: 0.698), // marine blue
        .init(r: 0.031, g: 0.557, b: 0.808), // cerulean
        .init(r: 0.102, g: 0.749, b: 0.620), // aqua green
        .init(r: 0.678, g: 0.863, b: 0.196), // chartreuse
        .init(r: 0.984, g: 0.816, b: 0.129), // sunflower
        .init(r: 0.984, g: 0.463, b: 0.165), // tangerine
        .init(r: 0.933, g: 0.102, b: 0.325)  // raspberry
    ]
    
    private static let windGustPalette: [RGB] = [
        .init(r: 0.231, g: 0.105, b: 0.678), // electric indigo
        .init(r: 0.231, g: 0.337, b: 0.788), // royal blue
        .init(r: 0.129, g: 0.611, b: 0.843), // bright azure
        .init(r: 0.102, g: 0.769, b: 0.596), // vivid teal
        .init(r: 0.992, g: 0.855, b: 0.173), // bright yellow
        .init(r: 0.984, g: 0.545, b: 0.173), // vivid orange
        .init(r: 0.925, g: 0.196, b: 0.333), // bold red
        .init(r: 0.682, g: 0.078, b: 0.482)  // hot magenta
    ]
    
    private static func normalizedFraction(value: Double?, lowerBound: Double, upperBound: Double) -> Double {
        guard let value else { return 0 }
        if upperBound <= lowerBound { return 0 }
        return min(max((value - lowerBound) / (upperBound - lowerBound), 0), 1)
    }
    
    private static func interpolateColor(in palette: [RGB], fraction rawFraction: Double) -> Color {
        guard !palette.isEmpty else { return .white }
        let clamped = min(max(rawFraction, 0), 1)
        let scaled = clamped * Double(max(palette.count - 1, 1))
        let lowerIndex = Int(floor(scaled))
        let upperIndex = min(lowerIndex + 1, palette.count - 1)
        let interpolation = scaled - Double(lowerIndex)
        let lower = palette[lowerIndex]
        let upper = palette[upperIndex]
        let r = lower.r + (upper.r - lower.r) * interpolation
        let g = lower.g + (upper.g - lower.g) * interpolation
        let b = lower.b + (upper.b - lower.b) * interpolation
        return Color(red: r, green: g, blue: b)
    }
    
    // MARK: - Wave Styling
    
    static func waveHeightColor(for height: Double?) -> Color {
        let fraction = pow(normalizedFraction(value: height, lowerBound: 1, upperBound: 20), 0.75)
        return interpolateColor(in: waveHeightPalette, fraction: fraction)
    }
    
    static func wavePeriodColor(for period: Double?) -> Color {
        let fraction = pow(normalizedFraction(value: period, lowerBound: 8, upperBound: 22), 0.8)
        // Long-period = calmer -> warmer
        return interpolateColor(in: wavePeriodPalette, fraction: fraction)
    }
    
    // MARK: - Wind Styling
    
    static func windSpeedColor(for speed: Double?) -> Color {
        let fraction = pow(normalizedFraction(value: speed, lowerBound: 5, upperBound: 35), 0.72)
        return interpolateColor(in: windSpeedPalette, fraction: fraction)
    }
    
    static func windGustColor(for gust: Double?) -> Color {
        let fraction = pow(normalizedFraction(value: gust, lowerBound: 10, upperBound: 55), 0.7)
        return interpolateColor(in: windGustPalette, fraction: fraction)
    }
}
