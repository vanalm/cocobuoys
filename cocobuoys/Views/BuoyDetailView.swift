//
//  BuoyDetailView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import SwiftUI
import Charts

struct BuoyDetailView: View {
    let buoy: Buoy
    @State private var selectedObservation: BuoyObservation?
    
    private var observations: [BuoyObservation] {
        let slice = buoy.observations.suffix(24)
        return Array(slice)
    }
    
    private var displayObservation: BuoyObservation? {
        selectedObservation ?? buoy.latestObservation
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chartSection
            if let observation = displayObservation {
                detailSection(for: observation)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(.regularMaterial)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(buoy.name)
                .font(.title3.weight(.semibold))
            if let latest = buoy.latestObservation {
                Text("Updated \(formattedDate(latest.timestamp))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var chartSection: some View {
        if observations.isEmpty {
            Text("No recent readings available.")
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else {
            chartView
        }
    }
    
    private var chartView: some View {
        let tickDates = sampledTickDates()
        return Chart {
            ForEach(observations) { observation in
                if let height = observation.heightFeet {
                    LineMark(
                        x: .value("Time", observation.timestamp),
                        y: .value("Wave Height (ft)", height)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue)
                    .lineStyle(.init(lineWidth: 2))
                }
                if let period = observation.periodSeconds {
                    LineMark(
                        x: .value("Time", observation.timestamp),
                        y: .value("Period (s)", period)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.orange)
                    .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            if let selected = selectedObservation {
                RuleMark(x: .value("Selected", selected.timestamp))
                    .lineStyle(.init(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.secondary)
                if let height = selected.heightFeet {
                    PointMark(
                        x: .value("Time", selected.timestamp),
                        y: .value("Wave Height (ft)", height)
                    )
                    .symbolSize(60)
                    .foregroundStyle(Color.blue)
                }
                if let period = selected.periodSeconds {
                    PointMark(
                        x: .value("Time", selected.timestamp),
                        y: .value("Period (s)", period)
                    )
                    .symbolSize(60)
                    .foregroundStyle(Color.orange)
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .chartXAxis {
            AxisMarks(values: tickDates) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                    }
                }
            }
        }
        .frame(height: 220)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateSelection(at: value.location, proxy: proxy, geometry: geo)
                            }
                            .onEnded { _ in }
                    )
            }
        }
    }

    private func sampledTickDates() -> [Date] {
        var seen = Set<Date>()
        var ordered: [Date] = []
        for observation in observations {
            let timestamp = observation.timestamp
            if !seen.contains(timestamp) {
                seen.insert(timestamp)
                ordered.append(timestamp)
            }
        }
        guard ordered.count > maxAxisTicks else { return ordered }
        let stride = max(1, ordered.count / maxAxisTicks)
        var sampled: [Date] = []
        for (index, date) in ordered.enumerated() where index % stride == 0 {
            sampled.append(date)
        }
        if let last = ordered.last, sampled.last != last {
            sampled.append(last)
        }
        return sampled
    }
    
    private func axisLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
    
    private var maxAxisTicks: Int { 12 }
    
    private func detailSection(for observation: BuoyObservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formattedDateTime(observation.timestamp))
                .font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Wave Height")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(formattedHeight(observation.heightFeet))
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Period")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(formattedPeriod(observation.periodSeconds))
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Direction")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(observation.directionCardinal ?? "–")
                        .font(.title3.weight(.semibold))
                }
            }
            if let waterTemp = observation.waterTemperatureFahrenheit {
                Text("Water Temp: \(String(format: "%.1f°F", waterTemp))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame: CGRect
        if #available(iOS 17.0, *) {
            plotFrame = geometry[proxy.plotFrame!]
        } else {
            plotFrame = geometry[proxy.plotAreaFrame]
        }
        let translatedPoint = CGPoint(
            x: location.x - plotFrame.origin.x,
            y: location.y - plotFrame.origin.y
        )
        guard translatedPoint.x >= 0,
              translatedPoint.y >= 0,
              translatedPoint.x <= plotFrame.size.width,
              translatedPoint.y <= plotFrame.size.height else {
            return
        }
        let date: Date?
        if #available(iOS 17.0, *) {
            date = proxy.value(atX: translatedPoint.x, as: Date.self)
        } else {
            date = proxy.value(atX: translatedPoint.x)
        }
        if let date {
            selectedObservation = nearestObservation(to: date)
        }
    }
    
    private func nearestObservation(to date: Date) -> BuoyObservation? {
        observations.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedHeight(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f ft", value)
    }
    
    private func formattedPeriod(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f s", value)
    }
}

#Preview {
    let sampleObservations: [BuoyObservation] = stride(from: 0, to: 12, by: 1).compactMap { index in
        let timestamp = Calendar.current.date(byAdding: .hour, value: -index, to: .now) ?? .now
        return BuoyObservation(
            id: UUID().uuidString,
            timestamp: timestamp,
            heightFeet: Double.random(in: 2.0...8.0),
            periodSeconds: Double.random(in: 10...18),
            directionCardinal: "NW",
            waterTemperatureFahrenheit: 76.0,
            windSpeedKnots: Double.random(in: 5...20),
            windGustKnots: Double.random(in: 10...30),
            directionDegrees: 315,
            windDirectionCardinal: "NE",
            windDirectionDegrees: 45
        )
    }
    let buoy = Buoy(
        id: "51202",
        name: "Buoy 51202",
        coordinate: .init(latitude: 21.41, longitude: -157.68),
        observations: sampleObservations,
        lastUpdated: sampleObservations.last?.timestamp
    )
    return BuoyDetailView(buoy: buoy)
}
