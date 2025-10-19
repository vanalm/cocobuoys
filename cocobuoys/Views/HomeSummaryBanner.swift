//
//  HomeSummaryBanner.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import SwiftUI

struct HomeSummaryBanner: View {
    let summary: HomeSummary
    var onUpdate: () -> Void
    var onClear: () -> Void
    var onTitleTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onTitleTap) {
                    Text("Home Conditions")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("Update", action: onUpdate)
                    Button("Clear", role: .destructive, action: onClear)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.medium)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if hasWaveData {
                    sectionHeader(title: "Waves", detail: summary.waveStationName)
                    HStack(spacing: 16) {
                        metric(title: "Height", value: waveDescription)
                        metric(title: "Period", value: periodDescription)
                        metric(title: "Dir", value: summary.waveDirectionCardinal ?? "–")
                    }
                }
                if hasWindData {
                    sectionHeader(title: "Wind", detail: summary.windStationName)
                    HStack(spacing: 16) {
                        metric(title: "Speed", value: windDescription)
                        metric(title: "Dir", value: summary.windDirectionCardinal ?? "–")
                        metric(title: "Gust", value: gustDescription)
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
    }
    
    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
        }
    }
    
    private var waveDescription: String {
        guard let height = summary.waveHeightFeet else { return "–" }
        return String(format: "%.1f ft", height)
    }
    
    private var periodDescription: String {
        guard let period = summary.wavePeriodSeconds else { return "–" }
        return String(format: "%.1f s", period)
    }
    
    private var windDescription: String {
        guard let speed = summary.windSpeedKnots else { return "–" }
        if let direction = summary.windDirectionCardinal {
            return String(format: "%.0f kt %@", speed, direction)
        }
        return String(format: "%.0f kt", speed)
    }
    
    private var gustDescription: String {
        guard let gust = summary.windGustKnots else { return "–" }
        return String(format: "%.0f kt", gust)
    }
    
    private var hasWaveData: Bool {
        summary.waveStationName != nil
    }
    
    private var hasWindData: Bool {
        summary.windStationName != nil
    }
    
    private func sectionHeader(title: String, detail: String?) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HomeSummaryBanner(
        summary: HomeSummary(
            waveStationName: "Buoy 51205",
            waveHeightFeet: 4.2,
            wavePeriodSeconds: 14.3,
            waveDirectionCardinal: "NW",
            windStationName: "Station KLIH1",
            windSpeedKnots: 18,
            windDirectionCardinal: "NE",
            windGustKnots: 24
        ),
        onUpdate: {},
        onClear: {},
        onTitleTap: {}
    )
    .padding()
    .background(Color.black.opacity(0.1))
}
