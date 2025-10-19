//
//  StationDetailView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import SwiftUI
import Charts
import CoreLocation

private enum ChartInteractionMode: String, CaseIterable, Identifiable {
    case selection
    case pan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .selection: return "Select"
        case .pan: return "Pan"
        }
    }
}

struct StationDetailView: View {
    @StateObject private var viewModel: StationHistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var interactionMode: ChartInteractionMode = .selection
    @State private var visibleDomain: ClosedRange<Date>?
    @State private var defaultDomain: ClosedRange<Date>?
    @State private var panStartDomain: ClosedRange<Date>?
    @State private var lastScale: CGFloat = 1
    
    init(station: Buoy, service: NOAANdbcServicing) {
        _viewModel = StateObject(wrappedValue: StationHistoryViewModel(station: station, service: service))
    }
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                observationSummary
                metricPicker
                interactionModePicker
                chartSection
                Spacer(minLength: 0)
            }
            .padding(20)
            .task {
                await viewModel.load()
                refreshTimeDomain()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onReceive(viewModel.$history) { _ in
                refreshTimeDomain()
            }
        }
        .presentationDetents([.large, .fraction(0.6)])
        .presentationDragIndicator(.visible)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.station.name)
                .font(.title3.weight(.semibold))
            if let latest = viewModel.history.last?.timestamp {
                Text("Updated \(formattedDate(latest))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var metricPicker: some View {
        Group {
            if viewModel.availableMetrics.isEmpty {
                Text("No metrics available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.availableMetrics) { metric in
                            let isSelected = viewModel.selectedMetrics.contains(metric)
                            Button {
                                viewModel.toggleMetric(metric)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(metric.color)
                                        .frame(width: 10, height: 10)
                                    Text(metric.label)
                                        .font(.caption.weight(.semibold))
                                    Text(metric.unit)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(isSelected ? metric.color.opacity(0.15) : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    private var interactionModePicker: some View {
        Picker("Interaction", selection: $interactionMode) {
            ForEach(ChartInteractionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var observationSummary: some View {
        Group {
            if let observation = viewModel.selectedObservation ?? viewModel.history.last,
               !viewModel.selectedMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formattedDateTime(observation.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(viewModel.selectedMetrics, id: \.self) { metric in
                            if let value = metric.value(for: observation) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(formattedValue(value, unit: metric.unit))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(metric.color)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    @ViewBuilder
    private var chartSection: some View {
        if viewModel.isLoading && viewModel.history.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if viewModel.history.isEmpty {
            Text("No history available.")
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else {
            chartView
        }
    }
    
    private var chartView: some View {
        let metrics = viewModel.selectedMetrics
        let history = viewModel.history
        let timeDomain = visibleDomain ?? defaultDomain ?? fallbackTimeDomain()
        return ZStack {
            if shouldCombineWindAxes(metrics: metrics, history: history) {
                combinedWindChart(metrics: metrics, xDomain: timeDomain, history: history)
            } else {
                if let primary = metrics.first,
                   let primaryDomain = domain(for: primary, history: history) {
                    primarySeriesChart(metric: primary, yDomain: primaryDomain, xDomain: timeDomain, history: history)
                }
                if metrics.count > 1,
                   let secondaryDomain = domain(for: metrics[1], history: history) {
                    secondarySeriesChart(metric: metrics[1], yDomain: secondaryDomain, xDomain: timeDomain, history: history)
                }
            }
        }
        .frame(height: 240)
    }
    
    private func domain(for metric: StationMetric, history: [BuoyObservation]) -> ClosedRange<Double>? {
        let values = history.compactMap { metric.value(for: $0) }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        let span = maxValue - minValue
        let padding: Double
        if span == 0 {
            let baseline = max(abs(minValue), 1.0)
            padding = baseline * 0.1
        } else {
            padding = span * 0.1
        }
        let lower = minValue - padding
        let upper = maxValue + padding
        if lower == upper {
            return (lower - 1)...(upper + 1)
        }
        return lower...upper
    }
    
    private func shouldCombineWindAxes(metrics: [StationMetric], history: [BuoyObservation]) -> Bool {
        let set = Set(metrics)
        return set.contains(.windSpeed) && set.contains(.windGust) && metrics.count <= 2
    }
    
    private func combinedDomain(for metrics: [StationMetric], history: [BuoyObservation]) -> ClosedRange<Double>? {
        let values = history.compactMap { observation -> Double? in
            for metric in metrics {
                if let value = metric.value(for: observation) {
                    return value
                }
            }
            return nil
        }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        let span = maxValue - minValue
        let padding: Double = span == 0 ? max(abs(minValue), 1) * 0.1 : span * 0.1
        let lower = minValue - padding
        let upper = maxValue + padding
        if lower == upper {
            return (lower - 1)...(upper + 1)
        }
        return lower...upper
    }
    
    @ViewBuilder
    private func primarySeriesChart(metric: StationMetric, yDomain: ClosedRange<Double>, xDomain: ClosedRange<Date>, history: [BuoyObservation]) -> some View {
        Chart {
            ForEach(history, id: \.id) { observation in
                if let value = metric.value(for: observation) {
                    LineMark(
                        x: .value("Time", observation.timestamp),
                        y: .value(metric.label, value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.color)
                    .lineStyle(.init(lineWidth: 2))
                }
            }
            if let selected = viewModel.selectedObservation,
               let value = metric.value(for: selected) {
                RuleMark(x: .value("Selected", selected.timestamp))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(.init(lineWidth: 1, dash: [3, 4]))
                PointMark(
                    x: .value("Time", selected.timestamp),
                    y: .value(metric.label, value)
                )
                .symbolSize(70)
                .foregroundStyle(metric.color)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                interactionOverlay(proxy: proxy, geo: geo, xDomain: xDomain)
            }
        }
    }
    
    @ViewBuilder
    private func secondarySeriesChart(metric: StationMetric, yDomain: ClosedRange<Double>, xDomain: ClosedRange<Date>, history: [BuoyObservation]) -> some View {
        Chart {
            ForEach(history, id: \.id) { observation in
                if let value = metric.value(for: observation) {
                    LineMark(
                        x: .value("Time", observation.timestamp),
                        y: .value(metric.label, value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.color)
                    .lineStyle(.init(lineWidth: 2, dash: [4, 3]))
                }
            }
            if let selected = viewModel.selectedObservation,
               let value = metric.value(for: selected) {
                PointMark(
                    x: .value("Time", selected.timestamp),
                    y: .value(metric.label, value)
                )
                .symbolSize(70)
                .foregroundStyle(metric.color)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing)
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func combinedWindChart(metrics: [StationMetric], xDomain: ClosedRange<Date>, history: [BuoyObservation]) -> some View {
        let domainMetrics = metrics.filter { $0 == .windSpeed || $0 == .windGust }
        if let yDomain = combinedDomain(for: domainMetrics, history: history) {
            Chart {
                ForEach(domainMetrics, id: \.self) { metric in
                    let dash: [CGFloat] = metric == .windGust ? [4, 3] : []
                    ForEach(history, id: \.id) { observation in
                        if let value = metric.value(for: observation) {
                            LineMark(
                                x: .value("Time", observation.timestamp),
                                y: .value(metric.label, value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(metric.color)
                            .lineStyle(.init(lineWidth: 2, dash: dash))
                        }
                    }
                }
                if let selected = viewModel.selectedObservation {
                    RuleMark(x: .value("Selected", selected.timestamp))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(.init(lineWidth: 1, dash: [3, 4]))
                    ForEach(domainMetrics, id: \.self) { metric in
                        if let value = metric.value(for: selected) {
                            PointMark(
                                x: .value("Time", selected.timestamp),
                                y: .value(metric.label, value)
                            )
                            .symbolSize(70)
                            .foregroundStyle(metric.color)
                        }
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartPlotStyle { plotArea in
                plotArea.background(.clear)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    interactionOverlay(proxy: proxy, geo: geo, xDomain: xDomain)
                }
            }
        }
    }
    
    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame: CGRect
        if #available(iOS 17.0, *) {
            guard let anchor = proxy.plotFrame else { return }
            plotFrame = geometry[anchor]
        } else {
            plotFrame = geometry[proxy.plotAreaFrame]
        }
        let translated = CGPoint(x: location.x - plotFrame.origin.x, y: location.y - plotFrame.origin.y)
        guard translated.x >= 0, translated.y >= 0,
              translated.x <= plotFrame.width, translated.y <= plotFrame.height else {
            return
        }
        let date: Date?
        if #available(iOS 17.0, *) {
            date = proxy.value(atX: translated.x, as: Date.self)
        } else {
            date = proxy.value(atX: translated.x)
        }
        if let date {
            viewModel.setSelectedObservation(date: date)
        }
    }
    
    private func handleZoom(scale: CGFloat) {
        guard var domain = visibleDomain ?? defaultDomain ?? initialTimeDomain() else { return }
        guard scale.isFinite, scale > 0 else { return }
        let factor = scale / lastScale
        lastScale = scale
        guard factor.isFinite, factor > 0 else { return }
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return }
        var newSpan = span / Double(factor)
        let minSpan: Double = 60
        newSpan = max(newSpan, minSpan)
        if let defaultDomain {
            let defaultSpan = defaultDomain.upperBound.timeIntervalSince(defaultDomain.lowerBound)
            newSpan = min(newSpan, defaultSpan)
        }
        let mid = domain.lowerBound.addingTimeInterval(span / 2)
        let lower = mid.addingTimeInterval(-newSpan / 2)
        let upper = mid.addingTimeInterval(newSpan / 2)
        domain = clampDomain(lower...upper)
        visibleDomain = domain
    }
    
    private func handlePan(translation: CGFloat, plotWidth: CGFloat) {
        guard plotWidth > 0 else { return }
        guard let base = panStartDomain ?? visibleDomain ?? defaultDomain ?? initialTimeDomain() else { return }
        let span = base.upperBound.timeIntervalSince(base.lowerBound)
        guard span > 0 else { return }
        let fraction = Double(translation / plotWidth)
        let offset = span * fraction
        let lower = base.lowerBound.addingTimeInterval(-offset)
        let upper = base.upperBound.addingTimeInterval(-offset)
        visibleDomain = clampDomain(lower...upper)
    }
    
    private func clampDomain(_ domain: ClosedRange<Date>) -> ClosedRange<Date> {
        guard let defaultDomain else { return domain }
        let minSpan: Double = 60
        var lower = domain.lowerBound
        var upper = domain.upperBound
        var span = upper.timeIntervalSince(lower)
        if span < minSpan {
            let mid = lower.addingTimeInterval(span / 2)
            lower = mid.addingTimeInterval(-minSpan / 2)
            upper = mid.addingTimeInterval(minSpan / 2)
            span = minSpan
        }
        if lower < defaultDomain.lowerBound {
            lower = defaultDomain.lowerBound
            upper = lower.addingTimeInterval(span)
        }
        if upper > defaultDomain.upperBound {
            upper = defaultDomain.upperBound
            lower = upper.addingTimeInterval(-span)
        }
        if upper <= lower {
            upper = lower.addingTimeInterval(minSpan)
        }
        return lower...upper
    }
    
    private func initialTimeDomain() -> ClosedRange<Date>? {
        let timestamps = viewModel.history.map { $0.timestamp }
        guard let minDate = timestamps.min(), let maxDate = timestamps.max(), minDate <= maxDate else { return nil }
        let span = maxDate.timeIntervalSince(minDate)
        let padding = span == 0 ? 3600 : span * 0.1
        let lower = minDate.addingTimeInterval(-padding)
        let upper = maxDate.addingTimeInterval(padding)
        return lower...upper
    }
    
    private func fallbackTimeDomain() -> ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-3600)...now
    }
    
    private func refreshTimeDomain() {
        let domain = initialTimeDomain()
        defaultDomain = domain
        visibleDomain = domain
    }
    
    @ViewBuilder
    private func interactionOverlay(proxy: ChartProxy, geo: GeometryProxy, xDomain: ClosedRange<Date>) -> some View {
        let baseOverlay = Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
        let magnification = MagnificationGesture()
            .onChanged { scale in
                handleZoom(scale: scale)
            }
            .onEnded { _ in
                lastScale = 1
            }
        if interactionMode == .pan {
            baseOverlay
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if panStartDomain == nil {
                                panStartDomain = visibleDomain ?? defaultDomain ?? xDomain
                            }
                            handlePan(translation: value.translation.width, plotWidth: geo.size.width)
                            viewModel.clearSelection()
                        }
                        .onEnded { _ in
                            panStartDomain = nil
                        }
                )
                .simultaneousGesture(magnification)
        } else {
            baseOverlay
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateSelection(at: value.location, proxy: proxy, geometry: geo)
                        }
                )
                .simultaneousGesture(magnification)
        }
    }
    
    private func formattedValue(_ value: Double, unit: String) -> String {
        if unit == "s" {
            return String(format: "%.1f %@", value, unit)
        } else if unit == "°F" {
            return String(format: "%.1f%@", value, unit)
        } else if unit == "mb" {
            return String(format: "%.0f %@", value, unit)
        }
        return String(format: "%.1f %@", value, unit)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let now = Date()
    let sampleObservations: [BuoyObservation] = stride(from: 0, to: 24, by: 1).compactMap { hour in
        let timestamp = Calendar.current.date(byAdding: .hour, value: -hour, to: now) ?? now
        return BuoyObservation(
            id: UUID().uuidString,
            timestamp: timestamp,
            heightFeet: Double.random(in: 2.5...8.0),
            periodSeconds: Double.random(in: 10...18),
            waterTemperatureFahrenheit: Double.random(in: 68...82),
            windSpeedKnots: Double.random(in: 5...25),
            windGustKnots: Double.random(in: 10...32),
            directionDegrees: 300,
            windDirectionCardinal: "NW",
            windDirectionDegrees: 300,
            airTemperatureFahrenheit: Double.random(in: 65...80),
            tideFeet: Double.random(in: -1.0...3.0)
        )
    }
    let buoy = Buoy(
        id: "51205",
        name: "Station 51205",
        coordinate: CLLocationCoordinate2D(latitude: 21.02, longitude: -156.42),
        observations: sampleObservations,
        lastUpdated: sampleObservations.last?.timestamp
    )
    StationDetailView(station: buoy, service: NOAANdbcService())
}
