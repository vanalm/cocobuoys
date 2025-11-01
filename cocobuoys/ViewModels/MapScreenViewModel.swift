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

private extension MKCoordinateRegion {
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        let latitudeSpan = span.latitudeDelta / 2
        let longitudeSpan = span.longitudeDelta / 2
        let minLatitude = center.latitude - latitudeSpan
        let maxLatitude = center.latitude + latitudeSpan
        let minLongitude = center.longitude - longitudeSpan
        let maxLongitude = center.longitude + longitudeSpan
        return coordinate.latitude >= minLatitude &&
            coordinate.latitude <= maxLatitude &&
            coordinate.longitude >= minLongitude &&
            coordinate.longitude <= maxLongitude
    }
}

@MainActor
final class MapScreenViewModel: ObservableObject {
    private struct CachedHistory {
        var observations: [BuoyObservation]
        var fetchedAt: Date
    }
    
    @Published var region: MKCoordinateRegion? {
        didSet { updateTimelapseCandidateCount() }
    }
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
                timelapseStations = visibleTimelapseBuoys()
                timelapseCandidateCount = timelapseStations.count
                timelapseLoadingCount = timelapseStations.count
                timelapseLoadingProgress = 0
                timelapseCurrentDate = nil
                startTimelapsePreparation()
            } else {
                historyLoadTask = nil
                timelapseStations = []
                timelapseProgress = 1.0
                timelapseCurrentDate = nil
                timelapseLoadingProgress = 1
                timelapseLoadingCount = 0
                updateTimelapseCandidateCount()
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
    @Published private(set) var timelapseCandidateCount: Int = 0
    @Published private(set) var timelapseLoadingCount: Int = 0
    
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
    private var timelapseStations: [Buoy] = []
    private var historyLoadTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }
    private var homeSummaryTask: Task<Void, Never>?
    private var homeSummaryGeneration = 0
    private let homeChartTargetSampleCount = 32
    private let homeChartFallbackSpacing: TimeInterval = 1800 // 30 minutes
    private let homeChartSmoothingWindow = 5
    
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
                guard let self = self else { return }
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
                guard let self = self else { return }
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
        updateTimelapseCandidateCount()
        updateHomeSummary()
    }
    
    private func waveMarkerColor(for period: Double?) -> Color {
        StationColorScale.wavePeriodColor(for: period)
    }
    
    private func waveMarkerSize(for height: Double?) -> CGFloat {
        guard let height else { return 20 }
        let clamped = min(max(height, 1), 20)
        let fraction = (clamped - 1) / 19
        let eased = pow(fraction, 0.8)
        let base: CGFloat = 18
        let growth: CGFloat = 36
        return base + CGFloat(eased) * growth
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
        homeSummaryTask?.cancel()
        homeSummaryTask = nil
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
    
    func refreshHomeConditions() {
        let referenceCoordinate: CLLocationCoordinate2D
        if let homeLocation {
            referenceCoordinate = homeLocation
        } else if let latest = locationManager.latestLocation {
            referenceCoordinate = latest.coordinate
        } else if let last = lastFetchedLocation?.coordinate {
            referenceCoordinate = last
        } else if let regionCenter = region?.center {
            referenceCoordinate = regionCenter
        } else {
            referenceCoordinate = fallbackCoordinate
        }
        lastFetchedLocation = CLLocation(latitude: referenceCoordinate.latitude, longitude: referenceCoordinate.longitude)
        refreshStations(near: referenceCoordinate)
    }
    
    private func startTimelapsePreparation() {
        if timelapseStations.isEmpty {
            timelapseRange = nil
            timelapseLoadingProgress = 1
            timelapseLoadingCount = 0
            rebuildAnnotations()
            return
        }
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
        let buoys = timelapseStations
        guard !buoys.isEmpty else {
            await MainActor.run {
                timelapseLoadingProgress = 1
                timelapseLoadingCount = 0
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
            timelapseLoadingCount = totalToFetch
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
                    timelapseLoadingCount = max(totalToFetch - completed, 0)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                completed += 1
                await MainActor.run {
                    let progressValue = totalToFetch == 0 ? 1 : Double(completed) / Double(totalToFetch)
                    timelapseLoadingProgress = progressValue
                    timelapseLoadingCount = max(totalToFetch - completed, 0)
                }
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
            timelapseLoadingCount = 0
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
    
    private func updateTimelapseCandidateCount() {
        let buoys = Array(buoyCache.values)
        guard let region else {
            timelapseCandidateCount = buoys.count
            return
        }
        let visibleCount = buoys.filter { region.contains(coordinate: $0.coordinate) }.count
        timelapseCandidateCount = visibleCount
    }
    
    private func visibleTimelapseBuoys() -> [Buoy] {
        let buoys = Array(buoyCache.values)
        guard let region else { return buoys }
        return buoys.filter { region.contains(coordinate: $0.coordinate) }
    }
    
    private func rebuildAnnotations() {
        let buoys = Array(buoyCache.values)
        let existingById = Dictionary(uniqueKeysWithValues: annotations.map { ($0.identifier, $0) })
        var newAnnotations: [StationAnnotation] = []
        if showWaveStations {
            for buoy in buoys {
                if let annotation = waveAnnotation(for: buoy, existing: existingById) {
                    newAnnotations.append(annotation)
                }
            }
        }
        if showWindStations {
            for buoy in buoys {
                if let annotation = windAnnotation(for: buoy, existing: existingById) {
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
    
    private func waveAnnotation(for buoy: Buoy, existing: [String: StationAnnotation]) -> StationAnnotation? {
        guard let observation = observation(for: buoy),
              observation.heightFeet != nil || observation.periodSeconds != nil else { return nil }
        let style = BuoyMarkerStyle(
            color: waveMarkerColor(for: observation.periodSeconds),
            opacity: 0.9,
            size: waveMarkerSize(for: observation.heightFeet),
            direction: observation.directionDegrees ?? 0
        )
        let identifier = "\(buoy.id)-wave"
        if let annotation = existing[identifier] {
            annotation.update(with: buoy, kind: .wave(style: style))
            return annotation
        }
        return StationAnnotation(station: buoy, kind: .wave(style: style))
    }
    
    private func windAnnotation(for buoy: Buoy, existing: [String: StationAnnotation]) -> StationAnnotation? {
        guard let observation = observation(for: buoy),
              observation.windSpeedKnots != nil || observation.windGustKnots != nil else { return nil }
        let style = WindMarkerStyle(
            speedKnots: observation.windSpeedKnots,
            gustKnots: observation.windGustKnots,
            direction: observation.windDirectionDegrees,
            color: WindMarkerStyle.color(speed: observation.windSpeedKnots, gust: observation.windGustKnots)
        )
        let identifier = "\(buoy.id)-wind"
        if let annotation = existing[identifier] {
            annotation.update(with: buoy, kind: .wind(style: style))
            return annotation
        }
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
        homeSummaryGeneration += 1
        let generation = homeSummaryGeneration
        homeSummaryTask = Task { [weak self] in
            guard let self = self else { return }
            let summary = await self.buildHomeSummary()
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard generation == self.homeSummaryGeneration else { return }
                self.homeSummary = summary
            }
        }
    }
    
    private func buildHomeSummary() async -> HomeSummary? {
        guard let homeLocation else { return nil }
        if Task.isCancelled { return nil }
        let waveStation = nearestBuoyWithSwell(to: homeLocation)
        let windStation = nearestBuoyWithWind(to: homeLocation)
        if waveStation == nil && windStation == nil {
            return nil
        }
        async let waveHistory = recentHistory(for: waveStation)
        async let windHistory = recentHistory(for: windStation)
        let waveObservations = await waveHistory
        let windObservations = await windHistory
        if Task.isCancelled { return nil }
        let waveSamples = makeWaveSamples(from: waveObservations)
        let windSamples = makeWindSamples(from: windObservations)
        let waveObservation = waveObservations.last ?? waveStation?.latestObservation
        let windObservation = windObservations.last ?? windStation?.latestWindObservation
        return HomeSummary(
            waveStationName: waveStation?.name,
            waveStationId: waveStation?.id,
            waveHeightFeet: waveObservation?.heightFeet,
            wavePeriodSeconds: waveObservation?.periodSeconds,
            waveDirectionCardinal: waveObservation?.directionCardinal,
            waveUpdatedAt: waveObservation?.timestamp ?? waveSamples.last?.timestamp,
            waveSamples: waveSamples,
            windStationName: windStation?.name,
            windStationId: windStation?.id,
            windSpeedKnots: windObservation?.windSpeedKnots,
            windDirectionCardinal: windObservation?.windDirectionCardinal,
            windGustKnots: windObservation?.windGustKnots,
            windUpdatedAt: windObservation?.timestamp ?? windSamples.last?.timestamp,
            windSamples: windSamples
        )
    }
    
    private func recentHistory(for station: Buoy?) async -> [BuoyObservation] {
        guard let station else { return [] }
        if let cached = historyCache[station.id]?.observations, !cached.isEmpty {
            return StationHistoryViewModel.recentObservations(from: cached)
        }
        do {
            let history = try await dataService.fetchStationHistory(stationId: station.id)
            let sorted = history.sorted { $0.timestamp < $1.timestamp }
            historyCache[station.id] = CachedHistory(observations: sorted, fetchedAt: Date())
            return StationHistoryViewModel.recentObservations(from: sorted)
        } catch {
            historyCache[station.id] = CachedHistory(observations: station.observations, fetchedAt: Date())
            return StationHistoryViewModel.recentObservations(from: station.observations)
        }
    }
    
    private func makeWaveSamples(from observations: [BuoyObservation]) -> [HomeSummary.WaveSample] {
        let usable = observations
            .filter { $0.heightFeet != nil || $0.periodSeconds != nil }
        guard !usable.isEmpty else { return [] }
        let timeline = resampledTimeline(from: usable, desiredCount: homeChartTargetSampleCount, fallbackSpacing: homeChartFallbackSpacing)
        let heights = timeline.map { interpolatedValue(at: $0, in: usable, keyPath: \.heightFeet) }
        let periods = timeline.map { interpolatedValue(at: $0, in: usable, keyPath: \.periodSeconds) }
        let smoothedHeights = smoothSeries(heights, windowSize: homeChartSmoothingWindow)
        let smoothedPeriods = smoothSeries(periods, windowSize: homeChartSmoothingWindow)
        var samples: [HomeSummary.WaveSample] = []
        samples.reserveCapacity(timeline.count)
        for index in timeline.indices {
            let sample = HomeSummary.WaveSample(
                timestamp: timeline[index],
                heightFeet: smoothedHeights[index],
                periodSeconds: smoothedPeriods[index]
            )
            if sample.heightFeet != nil || sample.periodSeconds != nil {
                samples.append(sample)
            }
        }
        return samples
    }
    
    private func makeWindSamples(from observations: [BuoyObservation]) -> [HomeSummary.WindSample] {
        let usable = observations
            .filter { $0.windSpeedKnots != nil || $0.windGustKnots != nil }
        guard !usable.isEmpty else { return [] }
        let timeline = resampledTimeline(from: usable, desiredCount: homeChartTargetSampleCount, fallbackSpacing: homeChartFallbackSpacing)
        let speeds = timeline.map { interpolatedValue(at: $0, in: usable, keyPath: \.windSpeedKnots) }
        let gusts = timeline.map { interpolatedValue(at: $0, in: usable, keyPath: \.windGustKnots) }
        let smoothedSpeeds = smoothSeries(speeds, windowSize: homeChartSmoothingWindow)
        let smoothedGusts = smoothSeries(gusts, windowSize: homeChartSmoothingWindow)
        var samples: [HomeSummary.WindSample] = []
        samples.reserveCapacity(timeline.count)
        for index in timeline.indices {
            let sample = HomeSummary.WindSample(
                timestamp: timeline[index],
                speedKnots: smoothedSpeeds[index],
                gustKnots: smoothedGusts[index]
            )
            if sample.speedKnots != nil || sample.gustKnots != nil {
                samples.append(sample)
            }
        }
        return samples
    }
    
    private func resampledTimeline(
        from observations: [BuoyObservation],
        desiredCount: Int,
        fallbackSpacing: TimeInterval
    ) -> [Date] {
        let timestamps = observations.map(\.timestamp)
        let uniqueTimes = Array(Set(timestamps)).sorted()
        guard !uniqueTimes.isEmpty else {
            let now = Date()
            return (0..<desiredCount).map { index in
                let offset = Double(index - (desiredCount - 1))
                return now.addingTimeInterval(offset * fallbackSpacing)
            }
        }
        if uniqueTimes.count == 1 {
            let base = uniqueTimes[0]
            return (0..<desiredCount).map { index in
                let offset = Double(index - (desiredCount - 1))
                return base.addingTimeInterval(offset * fallbackSpacing)
            }
        }
        let count = min(max(desiredCount, uniqueTimes.count), 64)
        guard let start = uniqueTimes.first, let end = uniqueTimes.last else { return uniqueTimes }
        let span = end.timeIntervalSince(start)
        if span < 1 {
            return (0..<count).map { index in
                let offset = Double(index - (count - 1))
                return end.addingTimeInterval(offset * fallbackSpacing)
            }
        }
        return (0..<count).map { index in
            let fraction = Double(index) / Double(max(count - 1, 1))
            return start.addingTimeInterval(span * fraction)
        }
    }
    
    private func interpolatedValue(
        at timestamp: Date,
        in observations: [BuoyObservation],
        keyPath: KeyPath<BuoyObservation, Double?>
    ) -> Double? {
        let samples = observations
            .compactMap { observation -> (Date, Double)? in
                guard let value = observation[keyPath: keyPath] else { return nil }
                return (observation.timestamp, value)
            }
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 {
            return samples[0].1
        }
        if timestamp <= samples[0].0 {
            return samples[0].1
        }
        if let last = samples.last, timestamp >= last.0 {
            return last.1
        }
        if let exact = samples.first(where: { $0.0 == timestamp }) {
            return exact.1
        }
        guard let upperIndex = samples.firstIndex(where: { $0.0 > timestamp }), upperIndex > 0 else {
            return samples.last?.1
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let totalInterval = upper.0.timeIntervalSince(lower.0)
        if totalInterval <= 0 {
            return lower.1
        }
        let elapsed = timestamp.timeIntervalSince(lower.0)
        let fraction = elapsed / totalInterval
        return lower.1 + (upper.1 - lower.1) * fraction
    }
    
    private func smoothSeries(_ values: [Double?], windowSize: Int) -> [Double?] {
        guard windowSize > 1 else { return values }
        let radius = max(1, windowSize / 2)
        var smoothed = values
        for index in values.indices {
            var weightedTotal = 0.0
            var weightSum = 0.0
            for offset in -radius...radius {
                let neighborIndex = index + offset
                guard neighborIndex >= 0, neighborIndex < values.count else { continue }
                guard let value = values[neighborIndex] else { continue }
                let distance = abs(offset)
                let weight = 1.0 / Double(distance + 1)
                weightedTotal += value * weight
                weightSum += weight
            }
            if weightSum > 0 {
                smoothed[index] = weightedTotal / weightSum
            } else {
                smoothed[index] = nil
            }
        }
        return smoothed
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
