//
//  TimelapseControlView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import SwiftUI

struct TimelapseControlView: View {
    @Binding var progress: Double
    let currentDate: Date?
    let loadingProgress: Double
    var onClose: () -> Void
    
    private var isLoading: Bool {
        loadingProgress < 0.999
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timelapse")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                }
            }
            if isLoading {
                Text("Loading station history…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: loadingProgress)
                    .progressViewStyle(.linear)
            } else if let date = currentDate {
                Text(dateFormatter.string(from: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No history available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $progress, in: 0...1)
                .disabled(isLoading || currentDate == nil)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    TimelapseControlView(progress: .constant(0.5), currentDate: Date(), loadingProgress: 0.5, onClose: {})
        .padding()
        .background(Color.black.opacity(0.1))
}
