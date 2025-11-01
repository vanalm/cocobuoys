//
//  HomeSummaryBanner.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import SwiftUI
import Foundation

struct HomeSummaryBanner: View {
    @Environment(\.openURL) private var openURL
    let summary: HomeSummary
    var onUpdate: () -> Void
    var onClear: () -> Void
    var onTitleTap: () -> Void
    var onClose: () -> Void
    
    private let chartHeight: CGFloat = 92
    
    @State private var highlightedWaveTimestamp: Date?
    @State private var highlightedWindTimestamp: Date?
    @State private var pendingStationId: String?
    @State private var showStationLinkPrompt = false
    @State private var showDiagnostics = false
    @State private var highlightRecentlyUpdated = false
    
    private var isNight: Bool {
        let referenceDate = summary.waveUpdatedAt ?? summary.windUpdatedAt ?? Date()
        let hour = Calendar.current.component(.hour, from: referenceDate)
        return hour >= 18 || hour < 6
    }
    
    private var currentWaveHeight: Double? {
        if let height = summary.waveHeightFeet {
            return height
        }
        return summary.waveSamples.last?.heightFeet
    }
    
    private var currentWavePeriod: Double? {
        summary.wavePeriodSeconds ?? summary.waveSamples.last?.periodSeconds
    }
    
    private var currentWindSpeed: Double? {
        if let speed = summary.windSpeedKnots {
            return speed
        }
        return summary.windSamples.last?.speedKnots
    }
    
    private var currentWindGust: Double? {
        summary.windGustKnots ?? summary.windSamples.last?.gustKnots
    }
    
    private var wavePrimaryColor: Color {
        StationColorScale.waveHeightColor(for: currentWaveHeight)
    }
    
    private var waveSecondaryColor: Color {
        StationColorScale.wavePeriodColor(for: currentWavePeriod)
    }
    
    private var windPrimaryColor: Color {
        StationColorScale.windSpeedColor(for: currentWindSpeed)
    }
    
    private var windSecondaryColor: Color {
        StationColorScale.windGustColor(for: currentWindGust ?? currentWindSpeed)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    clearHighlights()
                    onTitleTap()
                } label: {
                    Text("Home Conditions")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                if let updatedText = lastUpdatedDescription {
                    Text(updatedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showDiagnostics.toggle()
                } label: {
                    Image(systemName: showDiagnostics ? "info.circle.fill" : "info.circle")
                        .imageScale(.medium)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    clearHighlights()
                    onUpdate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    clearHighlights()
                    onClear()
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.medium)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    clearHighlights()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.medium)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if showDiagnostics {
                diagnosticsPanel
            }
            VStack(alignment: .leading, spacing: 6) {
                if hasWaveData {
                    sectionHeader(
                        title: "Waves",
                        direction: summary.waveDirectionCardinal,
                        stationName: summary.waveStationName,
                        stationId: summary.waveStationId,
                        accentColor: waveSecondaryColor
                    )
                    chartContainer(available: waveChartAvailable, highlightedTimestamp: $highlightedWaveTimestamp) {
                        waveChart
                    }
                }
                if hasWindData {
                    sectionHeader(
                        title: "Wind",
                        direction: summary.windDirectionCardinal,
                        stationName: summary.windStationName,
                        stationId: summary.windStationId,
                        accentColor: windSecondaryColor
                    )
                    chartContainer(available: windChartAvailable, highlightedTimestamp: $highlightedWindTimestamp) {
                        windChart
                    }
                }
                if !hasWaveData && !hasWindData {
                    Text("No recent conditions nearby.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture {
            if highlightRecentlyUpdated {
                highlightRecentlyUpdated = false
                return
            }
            if highlightedWaveTimestamp != nil || highlightedWindTimestamp != nil {
                clearHighlights()
            }
        }
        .confirmationDialog(
            "Open Station Page?",
            isPresented: $showStationLinkPrompt
        ) {
            if let stationId = pendingStationId, let url = stationURL(for: stationId) {
                Button("Open NOAA Station \(stationId)") {
                    openURL(url)
                    pendingStationId = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingStationId = nil
            }
        } message: {
            if let stationId = pendingStationId {
                Text("Would you like to open NOAA station \(stationId) in Safari?")
            }
        }
    }
    
    @ViewBuilder
    private func chartContainer<ChartContent: View>(
        available: Bool,
        highlightedTimestamp: Binding<Date?>,
        @ViewBuilder content: () -> ChartContent
    ) -> some View {
        Group {
            if available {
                content()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .overlay {
                        Text("No recent trend")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isNight ? Color(.secondarySystemBackground).opacity(0.26) : Color(.secondarySystemBackground).opacity(0.12))
                .overlay {
                    if isNight {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.28),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.softLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
        )
        .clipped()
    }
    
    private var lastUpdatedDescription: String? {
        guard let latest = [summary.waveUpdatedAt, summary.windUpdatedAt].compactMap({ $0 }).max() else { return nil }
        let interval = Date().timeIntervalSince(latest)
        if interval < 0 {
            return "Updated just now"
        }
        let minutes = Int(interval / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "Updated \(hours)h \(remainingMinutes)m ago"
            } else {
                return "Updated \(hours)h ago"
            }
        } else if minutes > 0 {
            return "Updated \(minutes)m ago"
        } else {
            let seconds = max(0, Int(interval))
            if seconds > 10 {
                return "Updated \(seconds)s ago"
            }
            return "Updated just now"
        }
    }
    
    private var waveChartAvailable: Bool { !waveSeries.isEmpty }
    private var windChartAvailable: Bool { !windSeries.isEmpty }
    
    private var waveSamples: [HomeSummary.WaveSample] {
        summary.waveSamples
            .filter { $0.heightFeet != nil || $0.periodSeconds != nil }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    private var windSamples: [HomeSummary.WindSample] {
        summary.windSamples
            .filter { $0.speedKnots != nil || $0.gustKnots != nil }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    private var waveXDomain: ClosedRange<Date>? {
        guard let first = waveSamples.first?.timestamp,
              let last = waveSamples.last?.timestamp else { return nil }
        if first == last {
            return defaultDateDomain(around: first)
        }
        return first...last
    }
    
    private var windXDomain: ClosedRange<Date>? {
        guard let first = windSamples.first?.timestamp,
              let last = windSamples.last?.timestamp else { return nil }
        if first == last {
            return defaultDateDomain(around: first)
        }
        return first...last
    }
    
    private var waveYDomain: ClosedRange<Double>? {
        let values = waveSamples.flatMap { sample -> [Double] in
            [sample.heightFeet, sample.periodSeconds].compactMap { $0 }
        }
        return paddedDomain(for: values)
    }
    
    private var windYDomain: ClosedRange<Double>? {
        let values = windSamples.flatMap { sample -> [Double] in
            [sample.speedKnots, sample.gustKnots].compactMap { $0 }
        }
        return paddedDomain(for: values)
    }
    
    private var waveTimeDomain: ClosedRange<Date> {
        waveXDomain ?? defaultDateDomain(around: waveSamples.last?.timestamp)
    }
    
    private var windTimeDomain: ClosedRange<Date> {
        windXDomain ?? defaultDateDomain(around: windSamples.last?.timestamp)
    }
    
    private var waveValueRangeUsed: ClosedRange<Double> {
        waveYDomain ?? defaultValueDomain
    }
    
    private var windValueRangeUsed: ClosedRange<Double> {
        windYDomain ?? defaultValueDomain
    }
    
    private var waveUniqueTimestamps: Int {
        Set(waveSamples.map(\.timestamp)).count
    }
    
    private var windUniqueTimestamps: Int {
        Set(windSamples.map(\.timestamp)).count
    }
    
    private var debugLines: [String] {
        var lines: [String] = []
        lines.append("Wave total: \(waveSamples.count) unique ts: \(waveUniqueTimestamps)")
        lines.append("Wave domain: \(format(range: waveTimeDomain)) span: \(format(duration: waveTimeDomain))")
        lines.append("Wave values: \(format(range: waveValueRangeUsed))")
        for series in waveSeries {
            lines.append("↳ \(series.label): \(series.points.count) pts | min \(format(value: series.points.map(\.value).min())) max \(format(value: series.points.map(\.value).max()))")
        }
        lines.append("Wind total: \(windSamples.count) unique ts: \(windUniqueTimestamps)")
        lines.append("Wind domain: \(format(range: windTimeDomain)) span: \(format(duration: windTimeDomain))")
        lines.append("Wind values: \(format(range: windValueRangeUsed))")
        for series in windSeries {
            lines.append("↳ \(series.label): \(series.points.count) pts | min \(format(value: series.points.map(\.value).min())) max \(format(value: series.points.map(\.value).max()))")
        }
        return lines
    }
    
    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(debugLines, id: \.self) { line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var waveSeries: [MiniLineChart.Series] {
        [
            MiniLineChart.Series(
                label: "Height",
                color: wavePrimaryColor,
                dash: nil,
                points: waveSamples.compactMap { sample in
                    sample.heightFeet.map { MiniLineChart.Sample(time: sample.timestamp, value: $0) }
                }
            ),
            MiniLineChart.Series(
                label: "Period",
                color: waveSecondaryColor,
                dash: [4, 3],
                points: waveSamples.compactMap { sample in
                    sample.periodSeconds.map { MiniLineChart.Sample(time: sample.timestamp, value: $0) }
                }
            )
        ].filter { !$0.points.isEmpty }
    }
    
    private var windSeries: [MiniLineChart.Series] {
        [
            MiniLineChart.Series(
                label: "Speed",
                color: windPrimaryColor,
                dash: nil,
                points: windSamples.compactMap { sample in
                    sample.speedKnots.map { MiniLineChart.Sample(time: sample.timestamp, value: $0) }
                }
            ),
            MiniLineChart.Series(
                label: "Gust",
                color: windSecondaryColor,
                dash: [4, 3],
                points: windSamples.compactMap { sample in
                    sample.gustKnots.map { MiniLineChart.Sample(time: sample.timestamp, value: $0) }
                }
            )
        ].filter { !$0.points.isEmpty }
    }
    
    private var waveChart: some View {
        labeledChart(
            series: waveSeries,
            timeDomain: waveTimeDomain,
            valueRange: waveValueRangeUsed,
            scaleMode: .perSeries,
            highlightedTimestamp: $highlightedWaveTimestamp,
            valueFormatter: formatWaveValue
        )
    }
    
    private var windChart: some View {
        labeledChart(
            series: windSeries,
            timeDomain: windTimeDomain,
            valueRange: windValueRangeUsed,
            scaleMode: .shared,
            highlightedTimestamp: $highlightedWindTimestamp,
            valueFormatter: formatWindValue
        )
    }
    
    private func paddedDomain(for values: [Double]) -> ClosedRange<Double>? {
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        if minValue == maxValue {
            let padding = max(0.5, abs(minValue) * 0.25)
            return (minValue - padding)...(minValue + padding)
        }
        let span = maxValue - minValue
        let padding = span * 0.2
        return (minValue - padding)...(maxValue + padding)
    }
    
    private func defaultDateDomain(around reference: Date?) -> ClosedRange<Date> {
        let center = reference ?? Date()
        let halfWindow: TimeInterval = 1800 // 30 minutes
        return center.addingTimeInterval(-halfWindow)...center.addingTimeInterval(halfWindow)
    }
    
    private var defaultValueDomain: ClosedRange<Double> {
        0...1
    }
    
    private func format(range: ClosedRange<Double>) -> String {
        "[\(format(value: range.lowerBound)) • \(format(value: range.upperBound))]"
    }
    
    private func format(duration range: ClosedRange<Date>) -> String {
        let seconds = max(0, range.upperBound.timeIntervalSince(range.lowerBound))
        if seconds >= 3600 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        } else if seconds >= 120 {
            let minutes = Int(seconds / 60)
            let remaining = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(remaining)s"
        } else {
            return "\(Int(seconds))s"
        }
    }
    
    private func format(range: ClosedRange<Date>) -> String {
        "\(format(date: range.lowerBound)) → \(format(date: range.upperBound))"
    }
    
    private func format(value: Double?) -> String {
        guard let value else { return "–" }
        return DiagnosticsFormatter.number.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
    
    private func format(date: Date) -> String {
        DiagnosticsFormatter.time.string(from: date)
    }
    private var hasWaveData: Bool {
        summary.waveStationName != nil || summary.waveStationId != nil
    }
    
    private var hasWindData: Bool {
        summary.windStationName != nil || summary.windStationId != nil
    }
    
    private func sectionHeader(
        title: String,
        direction: String?,
        stationName: String?,
        stationId: String?,
        accentColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let stationLabel = stationDisplayName(for: stationName, stationId: stationId) {
                if let stationId {
                    Button {
                        requestOpenStation(stationId)
                    } label: {
                        Text(stationLabel)
                            .font(.caption.weight(.semibold))
                            .underline()
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(stationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            } else {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            Spacer(minLength: 8)
            let descriptor: String = {
                if let direction, !direction.isEmpty {
                    return "\(title), \(direction)"
                }
                return title
            }()
            Text(descriptor)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
        }
    }
    
    private func stationDisplayName(for name: String?, stationId: String?) -> String? {
        if let name, !name.isEmpty {
            return name
        }
        if let stationId {
            return "Station \(stationId)"
        }
        return nil
    }
    
    private func requestOpenStation(_ stationId: String) {
        pendingStationId = stationId
        showStationLinkPrompt = true
    }
    
    private func stationURL(for stationId: String) -> URL? {
        let trimmed = stationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://www.ndbc.noaa.gov/station_page.php?station=\(trimmed)")
    }
    
    private func labeledChart(
        series: [MiniLineChart.Series],
        timeDomain: ClosedRange<Date>,
        valueRange: ClosedRange<Double>,
        scaleMode: MiniLineChart.ScaleMode,
        highlightedTimestamp: Binding<Date?>,
        valueFormatter: @escaping (MiniLineChart.Series, Double) -> String
    ) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let timestamps = uniqueTimestamps(in: series)
            let normalizedPositions = normalizedPositions(for: timestamps, within: timeDomain)
            let positions: [(time: Date, x: CGFloat)] = timestamps.map { time in
                let fraction = normalizedPositions[time] ?? 0.5
                return (time, CGFloat(fraction) * width)
            }
            let overlay = chartOverlay(
                for: series,
                valueRange: valueRange,
                scaleMode: scaleMode,
                height: height,
                normalizedPositions: normalizedPositions,
                targetTime: highlightedTimestamp.wrappedValue,
                valueFormatter: valueFormatter
            )
            let drag = DragGesture(minimumDistance: 0)
                .onChanged { value in
                    highlightRecentlyUpdated = true
                    guard !positions.isEmpty else { return }
                    let clampedX = min(max(0, value.location.x), width)
                    if let nearest = positions.min(by: { abs($0.x - clampedX) < abs($1.x - clampedX) }) {
                        highlightedTimestamp.wrappedValue = nearest.time
                    }
                }
                .onEnded { value in
                    highlightRecentlyUpdated = true
                    guard !positions.isEmpty else { return }
                    let clampedX = min(max(0, value.location.x), width)
                    if let nearest = positions.min(by: { abs($0.x - clampedX) < abs($1.x - clampedX) }) {
                        highlightedTimestamp.wrappedValue = nearest.time
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        highlightRecentlyUpdated = false
                    }
                }
            ZStack(alignment: .topTrailing) {
                MiniLineChart(
                    series: series,
                    timeDomain: timeDomain,
                    valueRange: valueRange,
                    scaleMode: scaleMode
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                if let cursor = overlay.cursor {
                    let cursorX = CGFloat(cursor.normalizedX) * width
                    Path { path in
                        path.move(to: CGPoint(x: cursorX, y: 0))
                        path.addLine(to: CGPoint(x: cursorX, y: height))
                    }
                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Text(cursor.timeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .position(
                            x: min(max(cursorX, 44), width - 44),
                            y: 14
                        )
                }
                ForEach(overlay.labels) { label in
                    Text(label.text)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(label.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .offset(y: label.offsetY)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag)
        }
        .frame(height: chartHeight)
    }
    
    private func chartOverlay(
        for series: [MiniLineChart.Series],
        valueRange: ClosedRange<Double>,
        scaleMode: MiniLineChart.ScaleMode,
        height: CGFloat,
        normalizedPositions: [Date: Double],
        targetTime: Date?,
        valueFormatter: (MiniLineChart.Series, Double) -> String
    ) -> ChartOverlayInfo {
        let labelHeight: CGFloat = 26
        var labels: [ChartValueLabel] = []
        let effectiveTime = targetTime ?? latestTimestamp(in: series)
        
        for line in series {
            guard !line.points.isEmpty else { continue }
            let range: ClosedRange<Double>
            if scaleMode == .perSeries {
                let values = line.points.map(\.value)
                range = MiniLineChart.seriesRange(for: values, fallback: valueRange)
            } else {
                range = valueRange
            }
            let sample: MiniLineChart.Sample?
            if let time = effectiveTime {
                sample = nearestSample(in: line.points, to: time)
            } else {
                sample = line.points.last
            }
            guard let valueSample = sample else { continue }
            let span = max(range.upperBound - range.lowerBound, 1e-6)
            let normalized = (valueSample.value - range.lowerBound) / span
            let clamped = min(max(normalized, 0), 1)
            var top = height * (1 - CGFloat(clamped)) - labelHeight / 2
            top = max(4, min(height - labelHeight - 4, top))
            let text = valueFormatter(line, valueSample.value)
            labels.append(ChartValueLabel(text: text, color: line.color, offsetY: top))
        }
        
        labels.sort { $0.offsetY < $1.offsetY }
        let minSpacing: CGFloat = 22
        if labels.count > 1 {
            for index in 1..<labels.count {
                let previous = labels[index - 1].offsetY
                if labels[index].offsetY - previous < minSpacing {
                    labels[index].offsetY = previous + minSpacing
                }
                labels[index].offsetY = min(labels[index].offsetY, height - labelHeight - 4)
            }
            if labels.count > 1 {
                for rawIndex in stride(from: labels.count - 2, through: 0, by: -1) {
                    let next = labels[rawIndex + 1].offsetY
                    if next - labels[rawIndex].offsetY < minSpacing {
                        labels[rawIndex].offsetY = next - minSpacing
                    }
                    labels[rawIndex].offsetY = max(labels[rawIndex].offsetY, 4)
                    labels[rawIndex].offsetY = min(labels[rawIndex].offsetY, height - labelHeight - 4)
                }
            }
        }
        
        var cursor: ChartCursor?
        if let highlight = targetTime, !normalizedPositions.isEmpty {
            let fraction: Double?
            if let direct = normalizedPositions[highlight] {
                fraction = direct
            } else {
                fraction = normalizedPositions.min { lhs, rhs in
                    abs(lhs.key.timeIntervalSince(highlight)) < abs(rhs.key.timeIntervalSince(highlight))
                }?.value
            }
            if let fraction {
                cursor = ChartCursor(
                    normalizedX: fraction,
                    timeText: DiagnosticsFormatter.time.string(from: highlight)
                )
            }
        }
        
        return ChartOverlayInfo(labels: labels, cursor: cursor)
    }
    
    private func uniqueTimestamps(in series: [MiniLineChart.Series]) -> [Date] {
        Array(Set(series.flatMap { $0.points.map(\.time) })).sorted()
    }
    
    private func normalizedPositions(for times: [Date], within domain: ClosedRange<Date>) -> [Date: Double] {
        guard !times.isEmpty else { return [:] }
        let duration = domain.upperBound.timeIntervalSince(domain.lowerBound)
        if duration <= 0 || times.count <= 1 {
            if times.count == 1 {
                return [times[0]: 0.5]
            }
            return Dictionary(uniqueKeysWithValues: times.enumerated().map { index, time in
                (time, Double(index) / Double(max(times.count - 1, 1)))
            })
        }
        return Dictionary(uniqueKeysWithValues: times.map { time in
            let offset = time.timeIntervalSince(domain.lowerBound)
            let normalized = min(max(offset / max(duration, 1), 0), 1)
            return (time, normalized)
        })
    }
    
    private func latestTimestamp(in series: [MiniLineChart.Series]) -> Date? {
        series.compactMap { $0.points.last?.time }.max()
    }
    
    private func nearestSample(in points: [MiniLineChart.Sample], to time: Date) -> MiniLineChart.Sample? {
        guard !points.isEmpty else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.time.timeIntervalSince(time)) < abs(rhs.time.timeIntervalSince(time))
        }
    }
    
    private func clearHighlights() {
        highlightedWaveTimestamp = nil
        highlightedWindTimestamp = nil
        highlightRecentlyUpdated = false
    }
    
    private func formatWaveValue(series: MiniLineChart.Series, value: Double) -> String {
        switch series.label {
        case "Height":
            return String(format: "%.1f ft", value)
        case "Period":
            return String(format: "%.1f s", value)
        default:
            return DiagnosticsFormatter.number.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }
    }
    
    private func formatWindValue(series: MiniLineChart.Series, value: Double) -> String {
        switch series.label {
        case "Speed", "Gust":
            return String(format: "%.0f kt", value)
        default:
            return DiagnosticsFormatter.number.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }
    }
    
    private struct ChartValueLabel: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
        var offsetY: CGFloat
    }
    
    private struct ChartOverlayInfo {
        let labels: [ChartValueLabel]
        let cursor: ChartCursor?
    }
    
    private struct ChartCursor {
        let normalizedX: Double
        let timeText: String
    }
    
}

private struct MiniLineChart: View {
    struct Sample: Hashable {
        let time: Date
        let value: Double
    }
    
    struct Series: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        let dash: [CGFloat]?
        let points: [Sample]
    }
    
    let series: [Series]
    let timeDomain: ClosedRange<Date>
    let valueRange: ClosedRange<Double>
    var scaleMode: ScaleMode = .shared
    
    private var activeSeries: [Series] {
        series.filter { !$0.points.isEmpty }
    }
    
    enum ScaleMode {
        case shared
        case perSeries
    }
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let rawDuration = timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound)
            let uniqueTimes = Array(Set(activeSeries.flatMap { $0.points.map(\.time) })).sorted()
            let useEvenSpacingForTimes = rawDuration <= 0 || uniqueTimes.count <= 1
            let timeLookup: [Date: Double] = {
                if uniqueTimes.isEmpty {
                    return [:]
                } else if useEvenSpacingForTimes {
                    guard uniqueTimes.count > 1 else {
                        return [uniqueTimes[0]: 0.5]
                    }
                    return Dictionary(uniqueKeysWithValues: uniqueTimes.enumerated().map { index, date in
                        (date, Double(index) / Double(max(uniqueTimes.count - 1, 1)))
                    })
                } else {
                    let duration = max(rawDuration, 1)
                    return Dictionary(uniqueKeysWithValues: uniqueTimes.map { date in
                        let offset = date.timeIntervalSince(timeDomain.lowerBound)
                        let fraction = min(max(offset / duration, 0), 1)
                        return (date, fraction)
                    })
                }
            }()
            let perSeriesRanges: [UUID: ClosedRange<Double>] = Dictionary(uniqueKeysWithValues: activeSeries.map { series in
                let values = series.points.map(\.value)
                return (series.id, MiniLineChart.seriesRange(for: values, fallback: valueRange))
            })
            ZStack(alignment: .topLeading) {
                ForEach(activeSeries) { line in
                    let duplicateBuckets = Dictionary(grouping: Array(line.points.enumerated()), by: { $0.element.time })
                    let scaledPoints = line.points.enumerated().map { index, sample -> CGPoint in
                        let baseTime = timeLookup[sample.time] ?? 0.5
                        let normalizedTime: Double
                        if let duplicates = duplicateBuckets[sample.time], duplicates.count > 1 {
                            let order = duplicates.firstIndex(where: { $0.offset == index }) ?? 0
                            let spread: Double = 0.02
                            let center = Double(duplicates.count - 1) / 2
                            normalizedTime = min(max(baseTime + (Double(order) - center) * spread, 0), 1)
                        } else if useEvenSpacingForTimes {
                            let denominator = max(line.points.count - 1, 1)
                            normalizedTime = denominator == 0 ? 0.5 : Double(index) / Double(denominator)
                        } else {
                            normalizedTime = baseTime
                        }
                        let seriesRange: ClosedRange<Double>
                        if scaleMode == .perSeries {
                            seriesRange = perSeriesRanges[line.id] ?? valueRange
                        } else {
                            seriesRange = valueRange
                        }
                        let span = max(seriesRange.upperBound - seriesRange.lowerBound, 1e-6)
                        let normalizedValue = (sample.value - seriesRange.lowerBound) / span
                        let clampedValue = min(max(normalizedValue, 0), 1)
                        let x = width * CGFloat(normalizedTime)
                        let y = height * (1 - CGFloat(clampedValue))
                        return CGPoint(x: x, y: y)
                    }
                    
                    if scaledPoints.count > 1 {
                        smoothedPath(for: scaledPoints)
                            .stroke(
                            line.color,
                            style: StrokeStyle(
                                lineWidth: 1.6,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: line.dash ?? []
                            )
                        )
                    }
                }
            }
            .frame(width: width, height: height)
            .clipped()
        }
    }
    
    static func seriesRange(for values: [Double], fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else { return fallback }
        if minValue == maxValue {
            let padding = max(0.5, abs(minValue) * 0.25)
            return (minValue - padding)...(minValue + padding)
        }
        let span = maxValue - minValue
        let padding = span * 0.2
        return (minValue - padding)...(maxValue + padding)
    }
    
    private func smoothedPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        let lastIndex = points.count - 1
        let tension: CGFloat = 0.6
        for index in 0..<lastIndex {
            let p0 = points[index == 0 ? index : index - 1]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[index + 2 <= lastIndex ? index + 2 : lastIndex]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * (tension / 6),
                y: p1.y + (p2.y - p0.y) * (tension / 6)
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * (tension / 6),
                y: p2.y - (p3.y - p1.y) * (tension / 6)
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

private enum DiagnosticsFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.minimumIntegerDigits = 1
        return formatter
    }()
}

#Preview {
    HomeSummaryBanner(
        summary: HomeSummary(
            waveStationName: "Buoy 51205",
            waveStationId: "51205",
            waveHeightFeet: 4.2,
            wavePeriodSeconds: 14.3,
            waveDirectionCardinal: "NW",
            waveUpdatedAt: Date().addingTimeInterval(-900),
            waveSamples: Array(stride(from: 0, to: 16, by: 1).map { index in
                let timestamp = Date().addingTimeInterval(Double(-index) * 900)
                return HomeSummary.WaveSample(
                    timestamp: timestamp,
                    heightFeet: Double.random(in: 3.0...7.0),
                    periodSeconds: Double.random(in: 10...20)
                )
            }.reversed()),
            windStationName: "Station KLIH1",
            windStationId: "KLIH1",
            windSpeedKnots: 18,
            windDirectionCardinal: "NE",
            windGustKnots: 24,
            windUpdatedAt: Date().addingTimeInterval(-600),
            windSamples: Array(stride(from: 0, to: 16, by: 1).map { index in
                let timestamp = Date().addingTimeInterval(Double(-index) * 900)
                return HomeSummary.WindSample(
                    timestamp: timestamp,
                    speedKnots: Double.random(in: 10...22),
                    gustKnots: Double.random(in: 15...28)
                )
            }.reversed())
        ),
        onUpdate: {},
        onClear: {},
        onTitleTap: {},
        onClose: {}
    )
    .padding()
    .background(Color.black.opacity(0.1))
}
