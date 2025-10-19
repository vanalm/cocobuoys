//
//  NOAANdbcService.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import CoreLocation

protocol NOAANdbcServicing {
    func fetchNearbyBuoys(latitude: Double, longitude: Double) async throws -> [Buoy]
    func fetchStationHistory(stationId: String) async throws -> [BuoyObservation]
}

enum NOAANdbcServiceError: Error, LocalizedError {
    case invalidResponse
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the buoy service."
        case .decodingFailed:
            return "Failed to decode buoy data."
        }
    }
}

/// Temporary service that proxies the SurfBuoys API until NOAA integration is ready.
final class NOAANdbcService: NOAANdbcServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = NOAANdbcService.iso8601Formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
    }
    
    func fetchNearbyBuoys(latitude: Double, longitude: Double) async throws -> [Buoy] {
        let latString = String(format: "%.6f", latitude)
        let lonString = String(format: "%.6f", longitude)
        guard let url = URL(string: "https://api.surfbuoys.com/nearby-buoys/\(latString)/\(lonString)") else {
            throw NOAANdbcServiceError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NOAANdbcServiceError.invalidResponse
        }
        
        do {
            let rawResponse = try decoder.decode(SurfBuoyPayload.self, from: data)
            return rawResponse.toDomain()
        } catch {
            print("Buoy decoding failed: \(error)")
            throw NOAANdbcServiceError.decodingFailed
        }
    }
    
    func fetchStationHistory(stationId: String) async throws -> [BuoyObservation] {
        guard let url = URL(string: "https://api.surfbuoys.com/wavedata/stationId/\(stationId)") else {
            throw NOAANdbcServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NOAANdbcServiceError.invalidResponse
        }
        do {
            let dictionary = try decoder.decode([String: [SurfBuoyObservationDTO]].self, from: data)
            let entries = dictionary[stationId] ?? []
            let observations = entries.compactMap { BuoyMapper.observation(from: $0) }
            return observations.sorted { $0.timestamp < $1.timestamp }
        } catch {
            print("History decoding failed: \(error)")
            throw NOAANdbcServiceError.decodingFailed
        }
    }
}

private extension NOAANdbcService {
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - DTOs

private struct SurfBuoyPayload: Decodable {
    let stations: [String: [SurfBuoyObservationDTO]]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dictionary = try? container.decode([String: [SurfBuoyObservationDTO]].self) {
            self.stations = dictionary
        } else {
            self.stations = [:]
        }
    }
    
    func toDomain() -> [Buoy] {
        stations.compactMap { stationId, observations in
            BuoyMapper.map(stationId: stationId, observations: observations)
        }
    }
}

private enum BuoyMapper {
    static func map(stationId: String, observations rawObservations: [SurfBuoyObservationDTO]) -> Buoy? {
        guard !rawObservations.isEmpty else { return nil }
        let collected = rawObservations.compactMap { observation(from: $0) }.sorted { $0.timestamp < $1.timestamp }
        guard !collected.isEmpty else { return nil }
        let coordinate = rawObservations.compactMap { entry -> CLLocationCoordinate2D? in
            guard let coords = entry.coords?.coordinates, coords.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
        }.first
        guard let coordinate else { return nil }
        let displayName = displayName(for: stationId)
        
        return Buoy(
            id: stationId,
            name: displayName,
            coordinate: coordinate,
            observations: collected,
            lastUpdated: collected.last?.timestamp
        )
    }
    
    static func observation(from entry: SurfBuoyObservationDTO) -> BuoyObservation? {
        guard let timestamp = entry.gmt ?? entry.updatedAt else { return nil }
        let swellDir = entry.swellDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        let windDir = entry.windDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BuoyObservation(
            id: entry.id ?? UUID().uuidString,
            timestamp: timestamp,
            heightFeet: parseNumber(entry.height),
            periodSeconds: parseNumber(entry.period),
            directionCardinal: swellDir,
            waterTemperatureFahrenheit: parseNumber(entry.waterTemp),
            windSpeedKnots: parseNumber(entry.windSpeed),
            windGustKnots: parseNumber(entry.windGust),
            directionDegrees: swellDir.flatMap(Self.directionDegrees(for:)),
            windDirectionCardinal: windDir,
            windDirectionDegrees: windDir.flatMap(Self.directionDegrees(for:)),
            airTemperatureFahrenheit: parseNumber(entry.airTemp),
            pressureMillibars: parseNumber(entry.pressure),
            pressureTendencyMillibars: parseNumber(entry.pressureTendency),
            salinityPSU: parseNumber(entry.salinity),
            tideFeet: parseNumber(entry.tide),
            visibilityNauticalMiles: parseNumber(entry.visibility)
        )
    }
    
    private static func directionDegrees(for cardinal: String) -> Double? {
        let lookup: [String: Double] = [
            "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5,
            "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
            "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5,
            "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5
        ]
        return lookup[cardinal.uppercased()]
    }
    
    private static func displayName(for stationId: String) -> String {
        "Station \(stationId)"
    }
    
    private static func parseNumber(_ value: String?) -> Double? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return Double(value)
    }
}

private struct SurfBuoyObservationDTO: Decodable {
    let id: String?
    let gmt: Date?
    let stationId: String?
    let height: String?
    let period: String?
    let swellDir: String?
    let waterTemp: String?
    let windDir: String?
    let windGust: String?
    let windSpeed: String?
    let airTemp: String?
    let pressure: String?
    let pressureTendency: String?
    let salinity: String?
    let tide: String?
    let visibility: String?
    let coords: CoordinatesDTO?
    let updatedAt: Date?
    
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gmt = "GMT"
        case stationId
        case height
        case period
        case swellDir
        case waterTemp
        case windDir
        case windGust
        case windSpeed
        case airTemp
        case pressure
        case pressureTendency
        case salinity
        case tide
        case visibility
        case coords
        case updatedAt
    }
}

private struct CoordinatesDTO: Decodable {
    let coordinates: [Double]
}
