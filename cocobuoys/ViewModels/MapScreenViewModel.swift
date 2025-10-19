//
//  MapScreenViewModel.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import Combine
import MapKit
import CoreLocation
import SwiftUI

enum MapBaseLayer: String, CaseIterable, Identifiable {
    case hybrid
    case street
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .hybrid: return "Satellite"
        case .street: return "Street (OSM)"
        }
    }
    
    var systemImage: String {
        switch self {
        case .hybrid: return "globe.americas.fill"
        case .street: return "map"
        }
    }
}

@MainActor
final class MapScreenViewModel: ObservableObject {
    private struct CachedHistory {
        var observations: [BuoyObservation]
        var fetchedAt: Date
    }
    
    @Published var region: MKCoordinateRegion?
    @Published private(set) var annotations: [StationAnnotation] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published var infoMessage: String?
    @Published var selectedBuoy: Buoy?
    @Published var showHomePrompt = false
    @Published private(set) var homeSummary: HomeSummary?
    @Published private(set) var homeLocation: CLLocationCoordinate2D?
    @Published var mapStyle: MapBaseLayer = .hybrid
    @Published var showWaveStations: Bool = true {
        didSet { rebuildAnnotations() }
    }
    @Published var showWindStations: Bool = true {
        didSet { rebuildAnnotations() }
    }
    @Published var isHomeBannerCollapsed = false
    @Published var activeStationForGraph: Buoy?
    @Published var isTimelapseActive = false {
        didSet {
            if isTimelapseActive {
                timelapseLoadingProgress = 0
                timelapseCurrentDate = nil
                startTimelapsePreparation()
            } else {
                historyLoadTask = nil
                timelapseProgress = 1.0
                timelapseCurrentDate = nil
                timelapseLoadingProgress = 1
                rebuildAnnotations()
            }
        }
    }
    @Published var timelapseProgress: Double = 1.0 {
        didSet {
            guard isTimelapseActive else { return }
            updateTimelapseDate()
        }
    }
    @Published private(set) var timelapseCurrentDate: Date?
    @Published private(set) var timelapseLoadingProgress: Double = 1
    
    private let locationManager: LocationManager
    let dataService: NOAANdbcServicing
    private let homeStore: HomeLocationStoring
    private var cancellables = Set<AnyCancellable>()
    private var buoyCache: [String: Buoy] = [:]
    private var lastFetchedLocation: CLLocation?
    private let fetchDistanceThreshold: CLLocationDistance = 20_000 // meters ~12 miles
    private let fallbackCoordinate = CLLocationCoordinate2D(latitude: 20.8338944, longitude: -156.3459584)
    private var pendingHomeLocation: CLLocationCoordinate2D?
    private var hasCenteredOnUser = false
    private var historyCache: [String: CachedHistory] = [:]
    private var timelapseRange: ClosedRange<Date>?
    private var historyLoadTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }
    
    init(
        locationManager: LocationManager = LocationManager(),
        dataService: NOAANdbcServicing = NOAANdbcService(),
        homeStore: HomeLocationStoring = HomeLocationStore()
    ) {
        self.locationManager = locationManager
        self.dataService = dataService
        self.homeStore = homeStore
        self.authorizationStatus = locationManager.authorizationStatus
        self.homeLocation = homeStore.load()
        observeLocationUpdates()
        loadPreviewData()
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            refreshStations(near: fallbackCoordinate)
            lastFetchedLocation = CLLocation(latitude: fallbackCoordinate.latitude, longitude: fallbackCoordinate.longitude)
        }
    }
    
    func requestLocationAccess() {
        locationManager.requestAuthorization()
    }
    
    func select(station: MarineStation) {
        guard let buoy = buoyCache[station.id] else { return }
        selectedBuoy = buoy
    }
    
    func clearSelection() {
        selectedBuoy = nil
    }
    
    private func observeLocationUpdates() {
        locationManager.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                authorizationStatus = status
                switch status {
                case .authorizedAlways, .authorizedWhenInUse:
                    if infoMessage == "Location access denied" {
                        infoMessage = nil
                    }
                case .denied:
                    infoMessage = "Location access denied"
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        locationManager.$latestLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self else { return }
                centerOnUserIfNeeded(location.coordinate)
                refreshStationsIfNeeded(near: location)
                maybePromptForHome(using: location)
            }
            .store(in: &cancellables)
    }
    
    private func refreshStationsIfNeeded(near location: CLLocation) {
        if let last = lastFetchedLocation, last.distance(from: location) < fetchDistanceThreshold {
            return
        }
        lastFetchedLocation = location
        refreshStations(near: location.coordinate)
    }
    
    private func loadPreviewData() {
        #if DEBUG
        let now = Date()
        let previewObservations: [BuoyObservation] = stride(from: 0, through: 10, by: 1).map { index in
            let timestamp = Calendar.current.date(byAdding: .hour, value: -index, to: now) ?? now
            return BuoyObservation(
                id: UUID().uuidString,
                timestamp: timestamp,
                heightFeet: Double.random(in: 2.0...9.0),
                periodSeconds: Double.random(in: 10...18),
                directionCardinal: "NW",
                waterTemperatureFahrenheit: 77.0,
                windSpeedKnots: nil,
                windGustKnots: nil,
                directionDegrees: 315,
                windDirectionCardinal: "NW",
                windDirectionDegrees: 315
            )
        }
        let sampleBuoy = Buoy(
            id: "46042",
            name: "Sample Monterey Buoy",
            coordinate: CLLocationCoordinate2D(latitude: 36.785, longitude: -122.302),
            observations: previewObservations,
            lastUpdated: previewObservations.last?.timestamp
        )
        updateAnnotations(with: [sampleBuoy])
        if !hasCenteredOnUser {
            region = MKCoordinateRegion(
                center: sampleBuoy.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
            )
        }
        #endif
        updateHomeSummary()
    }
    
    private func refreshStations(near coordinate: CLLocationCoordinate2D) {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let buoys = try await dataService.fetchNearbyBuoys(latitude: coordinate.latitude, longitude: coordinate.longitude)
                infoMessage = nil
                updateAnnotations(with: buoys)
            } catch {
                infoMessage = "Failed to load buoy data."
                print("Buoy refresh failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateAnnotations(with buoys: [Buoy]) {
        buoyCache = buoys.reduce(into: [:]) { partial, buoy in
            partial[buoy.id] = buoy
        }
        rebuildAnnotations()
    }
    
    private func color(for height: Double?) -> Color {
        guard let height else { return .gray }
        switch height {
        case ..<1:
            return .green
        case 1..<2.5:
            return .yellow
        default:
            return .red
        }
    }
    
    private func size(for period: Double?) -> CGFloat {
        guard let period else { return 12 }
        let minSize: CGFloat = 12
        let maxSize: CGFloat = 28
        let normalized = min(max(period, 5), 20)
        return minSize + (CGFloat(normalized - 5) / 15) * (maxSize - minSize)
    }

    func confirmHomeLocation() {
        guard let candidate = pendingHomeLocation else {
            showHomePrompt = false
            return
        }
        homeStore.save(candidate)
        homeLocation = candidate
        pendingHomeLocation = nil
        showHomePrompt = false
        updateHomeSummary()
    }
    
    func declineHomePrompt() {
        pendingHomeLocation = nil
        showHomePrompt = false
    }
    
    func clearHomeLocation() {
        homeStore.clear()
        homeLocation = nil
        homeSummary = nil
        pendingHomeLocation = nil
    }
    
    func requestHomeReassignment() {
        if let latest = locationManager.latestLocation ?? lastFetchedLocation {
            pendingHomeLocation = latest.coordinate
            showHomePrompt = true
        }
    }
    
    func select(mapStyle: MapBaseLayer) {
        self.mapStyle = mapStyle
    }

    func toggleWaveVisibility() {
        showWaveStations.toggle()
    }
    
    func toggleWindVisibility() {
        showWindStations.toggle()
    }
    
    func collapseHomeSummary() {
        isHomeBannerCollapsed = true
    }
    
    func expandHomeSummary() {
        isHomeBannerCollapsed = false
    }
    
    func openHomeGraph() {
        let reference = (homeLocation ?? region?.center) ?? fallbackCoordinate
        if let waveStation = nearestBuoyWithSwell(to: reference) {
            activeStationForGraph = waveStation
        }
    }
    
    func dismissGraph() {
        activeStationForGraph = nil
    }
    
    func toggleTimelapseMode() {
        isTimelapseActive.toggle()
    }
    
    private func startTimelapsePreparation() {
        timelapseLoadingProgress = 0
        historyLoadTask = Task {
            await preloadHistoriesIfNeeded()
            await MainActor.run {
                updateTimelapseDate()
                rebuildAnnotations()
            }
        }
    }
    
    private func preloadHistoriesIfNeeded() async {
        let buoys = Array(buoyCache.values)
        guard !buoys.isEmpty else {
            await MainActor.run {
                timelapseLoadingProgress = 1
                timelapseRange = nil
            }
            return
        }
        let now = Date()
        let idsNeedingFetch = Set(buoys.compactMap { buoy -> String? in
            if shouldFetchHistory(for: buoy, now: now) { return buoy.id }
            return nil
        })
        let totalToFetch = idsNeedingFetch.count
        await MainActor.run {
            timelapseLoadingProgress = totalToFetch == 0 ? 1 : 0
        }
        var globalMin: Date?
        var globalMax: Date?
        var completed = 0
        for buoy in buoys {
            if Task.isCancelled { return }
            if !idsNeedingFetch.contains(buoy.id), let cached = historyCache[buoy.id] {
                mergeRange(observations: cached.observations, into: &globalMin, &globalMax)
                continue
            }
            do {
                let history = try await dataService.fetchStationHistory(stationId: buoy.id)
                let sorted = history.sorted { $0.timestamp < $1.timestamp }
                historyCache[buoy.id] = CachedHistory(observations: sorted, fetchedAt: now)
                mergeRange(observations: sorted, into: &globalMin, &globalMax)
                completed += 1
                let progressValue = totalToFetch == 0 ? 1 : Double(completed) / Double(totalToFetch)
                await MainActor.run {
                    timelapseLoadingProgress = progressValue
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                continue
            }
        }
        if let minDate = globalMin, let maxDate = globalMax, minDate <= maxDate {
            timelapseRange = minDate...maxDate
        } else {
            let fallbackDates = buoys.flatMap { buoy -> [Date] in
                [buoy.observations.first?.timestamp, buoy.observations.last?.timestamp].compactMap { $0 }
            }
            if let minDate = fallbackDates.min(), let maxDate = fallbackDates.max(), minDate <= maxDate {
                timelapseRange = minDate...maxDate
            }
        }
        await MainActor.run {
            timelapseLoadingProgress = 1
        }
    }
    
    private func updateTimelapseDate() {
        guard let range = timelapseRange else {
            timelapseCurrentDate = nil
            rebuildAnnotations()
            return
        }
        let progress = max(0.0, min(1.0, timelapseProgress))
        let interval = range.upperBound.timeIntervalSince(range.lowerBound)
        let date = range.lowerBound.addingTimeInterval(interval * progress)
        timelapseCurrentDate = date
        rebuildAnnotations()
    }
    
    private func rebuildAnnotations() {
        let buoys = Array(buoyCache.values)
        var newAnnotations: [StationAnnotation] = []
        if showWaveStations {
            for buoy in buoys {
                if let annotation = waveAnnotation(for: buoy) {
                    newAnnotations.append(annotation)
                }
            }
        }
        if showWindStations {
            for buoy in buoys {
                if let annotation = windAnnotation(for: buoy) {
                    newAnnotations.append(annotation)
                }
            }
        }
        self.annotations = newAnnotations
        if let selectedId = selectedBuoy?.id,
           let updated = buoyCache[selectedId],
           showWaveStations,
           updated.hasWaveData {
            selectedBuoy = updated
        } else if selectedBuoy != nil {
            selectedBuoy = nil
        }
        updateHomeSummary()
    }
    
    private func waveAnnotation(for buoy: Buoy) -> StationAnnotation? {
        guard let observation = observation(for: buoy),
              observation.heightFeet != nil || observation.periodSeconds != nil else { return nil }
        let style = BuoyMarkerStyle(
            color: color(for: observation.heightMeters),
            opacity: 0.9,
            size: size(for: observation.periodSeconds),
            direction: observation.directionDegrees ?? 0
        )
        return StationAnnotation(station: buoy, kind: .wave(style: style))
    }
    
    private func windAnnotation(for buoy: Buoy) -> StationAnnotation? {
        guard let observation = observation(for: buoy),
              observation.windSpeedKnots != nil || observation.windGustKnots != nil else { return nil }
        let style = WindMarkerStyle(
            speedKnots: observation.windSpeedKnots,
            gustKnots: observation.windGustKnots,
            direction: observation.windDirectionDegrees,
            color: WindMarkerStyle.color(for: observation.windSpeedKnots)
        )
        return StationAnnotation(station: buoy, kind: .wind(style: style))
    }
    
    private func centerOnUserIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard !hasCenteredOnUser else { return }
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        hasCenteredOnUser = true
    }
    
    private func maybePromptForHome(using location: CLLocation) {
        guard homeLocation == nil, pendingHomeLocation == nil, !showHomePrompt else { return }
        pendingHomeLocation = location.coordinate
        showHomePrompt = true
    }
    
    private func updateHomeSummary() {
        guard let homeLocation else {
            homeSummary = nil
            return
        }
        let waveStation = nearestBuoyWithSwell(to: homeLocation)
        let windStation = nearestBuoyWithWind(to: homeLocation)
        if waveStation == nil && windStation == nil {
            homeSummary = nil
            return
        }
        let waveObservation = waveStation?.latestObservation
        let windObservation = windStation?.latestWindObservation
        homeSummary = HomeSummary(
            waveStationName: waveStation?.name,
            waveHeightFeet: waveObservation?.heightFeet,
            wavePeriodSeconds: waveObservation?.periodSeconds,
            waveDirectionCardinal: waveObservation?.directionCardinal,
            windStationName: windStation?.name,
            windSpeedKnots: windObservation?.windSpeedKnots,
            windDirectionCardinal: windObservation?.windDirectionCardinal,
            windGustKnots: windObservation?.windGustKnots
        )
    }

    private func nearestBuoyWithSwell(to coordinate: CLLocationCoordinate2D) -> Buoy? {
        guard !buoyCache.isEmpty else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = buoyCache.values.compactMap { buoy -> (Buoy, CLLocationDistance)? in
            guard let observation = observation(for: buoy, at: nil),
                  observation.heightFeet != nil || observation.periodSeconds != nil else { return nil }
            let location = CLLocation(latitude: buoy.coordinate.latitude, longitude: buoy.coordinate.longitude)
            return (buoy, location.distance(from: target))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }
    
    private func nearestBuoyWithWind(to coordinate: CLLocationCoordinate2D) -> Buoy? {
        guard !buoyCache.isEmpty else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = buoyCache.values.compactMap { buoy -> (Buoy, CLLocationDistance)? in
            guard let observation = observation(for: buoy, at: nil),
                  observation.windSpeedKnots != nil || observation.windGustKnots != nil else { return nil }
            let location = CLLocation(latitude: buoy.coordinate.latitude, longitude: buoy.coordinate.longitude)
            return (buoy, location.distance(from: target))
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private func observation(for buoy: Buoy, at overrideDate: Date? = nil) -> BuoyObservation? {
        if isTimelapseActive, let targetDate = overrideDate ?? timelapseCurrentDate {
            let history = historyCache[buoy.id]?.observations ?? buoy.observations
            return nearestObservation(in: history, to: targetDate)
        }
        return buoy.latestObservation
    }

    private func nearestObservation(in observations: [BuoyObservation], to date: Date) -> BuoyObservation? {
        guard !observations.isEmpty else { return nil }
        return observations.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    private func shouldFetchHistory(for buoy: Buoy, now: Date) -> Bool {
        guard let cached = historyCache[buoy.id] else { return true }
        return now.timeIntervalSince(cached.fetchedAt) > 900
    }
    
    private func mergeRange(observations: [BuoyObservation], into minDate: inout Date?, _ maxDate: inout Date?) {
        guard !observations.isEmpty else { return }
        if let first = observations.first?.timestamp, let last = observations.last?.timestamp {
            if minDate == nil || first < minDate! { minDate = first }
            if maxDate == nil || last > maxDate! { maxDate = last }
        } else {
            let timestamps = observations.map { $0.timestamp }
            if let minObs = timestamps.min() {
                if minDate == nil || minObs < minDate! { minDate = minObs }
            }
            if let maxObs = timestamps.max() {
                if maxDate == nil || maxObs > maxDate! { maxDate = maxObs }
            }
        }
    }
}
