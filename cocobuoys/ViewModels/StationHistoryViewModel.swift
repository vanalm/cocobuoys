//
//  StationHistoryViewModel.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import Combine
import SwiftUI

enum StationMetric: String, CaseIterable, Identifiable {
    case waveHeight
    case wavePeriod
    case waterTemp
    case windSpeed
    case windGust
    case airTemp
    case tide
    case pressure
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .waveHeight: return "Wave Height"
        case .wavePeriod: return "Wave Period"
        case .waterTemp: return "Water Temp"
        case .windSpeed: return "Wind Speed"
        case .windGust: return "Wind Gust"
        case .airTemp: return "Air Temp"
        case .tide: return "Tide"
        case .pressure: return "Pressure"
        }
    }
    
    var unit: String {
        switch self {
        case .waveHeight, .tide: return "ft"
        case .wavePeriod: return "s"
        case .waterTemp, .airTemp: return "°F"
        case .windSpeed, .windGust: return "kt"
        case .pressure: return "mb"
        }
    }
    
    var color: Color {
        switch self {
        case .waveHeight: return .blue
        case .wavePeriod: return .orange
        case .waterTemp: return .red
        case .windSpeed: return Color.cyan
        case .windGust: return Color.cyan.opacity(0.6)
        case .airTemp: return .pink
        case .tide: return .purple
        case .pressure: return .brown
        }
    }
    
    func value(for observation: BuoyObservation) -> Double? {
        switch self {
        case .waveHeight:
            return observation.heightFeet
        case .wavePeriod:
            return observation.periodSeconds
        case .waterTemp:
            return observation.waterTemperatureFahrenheit
        case .windSpeed:
            return observation.windSpeedKnots
        case .windGust:
            return observation.windGustKnots
        case .airTemp:
            return observation.airTemperatureFahrenheit
        case .tide:
            return observation.tideFeet
        case .pressure:
            return observation.pressureMillibars
        }
    }
}

@MainActor
final class StationHistoryViewModel: ObservableObject {
    @Published private(set) var history: [BuoyObservation] = []
    @Published private(set) var availableMetrics: [StationMetric] = []
    @Published var selectedMetrics: [StationMetric] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedObservation: BuoyObservation?
    
    let station: Buoy
    private let service: NOAANdbcServicing
    private let maxMetrics = 2
    
    init(station: Buoy, service: NOAANdbcServicing) {
        self.station = station
        self.service = service
    }
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let observations = try await service.fetchStationHistory(stationId: station.id)
            errorMessage = nil
            applyHistory(observations)
        } catch {
            errorMessage = "Unable to load station history."
            let fallback = station.observations
            applyHistory(fallback)
        }
    }
    
    func toggleMetric(_ metric: StationMetric) {
        if selectedMetrics.contains(metric) {
            selectedMetrics.removeAll { $0 == metric }
        } else {
            selectedMetrics.append(metric)
            if selectedMetrics.count > maxMetrics {
                selectedMetrics.removeFirst()
            }
        }
        ensureSelectedObservationValid()
    }
    
    static func recentObservations(
        from observations: [BuoyObservation],
        hours: Double = 24,
        minimumCount: Int = 8
    ) -> [BuoyObservation] {
        guard !observations.isEmpty else { return observations }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let filtered = observations.filter { $0.timestamp >= cutoff }
        if filtered.count >= minimumCount {
            return filtered
        }
        let lastSamples = Array(observations.suffix(max(minimumCount, filtered.count)))
        return lastSamples.isEmpty ? observations : lastSamples
    }
    
    private func applyHistory(_ observations: [BuoyObservation]) {
        history = Self.recentObservations(from: observations)
        availableMetrics = StationMetric.allCases.filter { metric in
            history.contains { metric.value(for: $0) != nil }
        }
        if selectedMetrics.isEmpty {
            selectedMetrics = Array(availableMetrics.prefix(maxMetrics))
        } else {
            selectedMetrics = selectedMetrics.filter { availableMetrics.contains($0) }
            if selectedMetrics.isEmpty {
                selectedMetrics = Array(availableMetrics.prefix(maxMetrics))
            }
        }
        ensureSelectedObservationValid()
    }
    
    func nearestObservation(to date: Date) -> BuoyObservation? {
        let pool = filteredHistoryForSelection()
        guard !pool.isEmpty else { return nil }
        return pool.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }
    
    func setSelectedObservation(date: Date) {
        selectedObservation = nearestObservation(to: date)
    }
    
    func clearSelection() {
        selectedObservation = nil
    }
    
    private func filteredHistoryForSelection() -> [BuoyObservation] {
        guard !selectedMetrics.isEmpty else { return history }
        return history.filter { observation in
            selectedMetrics.contains { $0.value(for: observation) != nil }
        }
    }
    
    private func ensureSelectedObservationValid() {
        let pool = filteredHistoryForSelection()
        guard !pool.isEmpty else {
            selectedObservation = nil
            return
        }
        if let current = selectedObservation,
           pool.contains(where: { $0.id == current.id }) {
            return
        }
        selectedObservation = pool.last
    }
}
