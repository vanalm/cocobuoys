//
//  ContentView.swift
//  cocobuoys
//
//  Created by Jacob van Almelo on 10/17/25.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var viewModel = MapScreenViewModel()
    
    var body: some View {
        ZStack(alignment: .top) {
            SatelliteMapView(
                region: $viewModel.region,
                annotations: viewModel.annotations,
                showsUserLocation: viewModel.authorizationStatus == .authorizedAlways || viewModel.authorizationStatus == .authorizedWhenInUse,
                mapStyle: viewModel.mapStyle,
                onSelectStation: { station in
                    viewModel.select(station: station)
                },
                onDeselectStation: {
                    viewModel.clearSelection()
                }
            )
            .ignoresSafeArea()
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !viewModel.isHomeBannerCollapsed && viewModel.homeSummary != nil {
                            viewModel.collapseHomeSummary()
                        }
                    }
            )
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Spacer()
                    Menu {
                        Button {
                            viewModel.toggleWaveVisibility()
                        } label: {
                            Label("Wave Markers", systemImage: viewModel.showWaveStations ? "checkmark.square" : "square")
                        }
                        Button {
                            viewModel.toggleWindVisibility()
                        } label: {
                            Label("Wind Markers", systemImage: viewModel.showWindStations ? "checkmark.square" : "square")
                        }
                        Divider()
                        Button {
                            viewModel.toggleTimelapseMode()
                        } label: {
                            Label(viewModel.isTimelapseActive ? "Disable Timelapse" : "Enable Timelapse", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .symbolRenderingMode(.hierarchical)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    Menu {
                        Button {
                            if viewModel.isHomeBannerCollapsed {
                                viewModel.expandHomeSummary()
                            } else {
                                viewModel.collapseHomeSummary()
                            }
                        } label: {
                            Label(viewModel.isHomeBannerCollapsed ? "Show Home Conditions" : "Hide Home Conditions", systemImage: "house")
                        }
                        ForEach(MapBaseLayer.allCases) { style in
                            Button {
                                viewModel.select(mapStyle: style)
                            } label: {
                                HStack {
                                    Label(style.title, systemImage: style.systemImage)
                                    if viewModel.mapStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.mapStyle.systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                if let summary = viewModel.homeSummary, !viewModel.isHomeBannerCollapsed {
                    HomeSummaryBanner(
                        summary: summary,
                        onUpdate: {
                            viewModel.requestHomeReassignment()
                        },
                        onClear: {
                            viewModel.clearHomeLocation()
                        },
                        onTitleTap: {
                            viewModel.expandHomeSummary()
                            viewModel.openHomeGraph()
                        }
                    )
                    .padding(.horizontal)
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                        .padding(.top, 4)
                }
                
                if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
                
                if viewModel.authorizationStatus == .notDetermined {
                    Button {
                        viewModel.requestLocationAccess()
                    } label: {
                        Label("Enable Location", systemImage: "location")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 32)
                }
            }
        }
        .sheet(item: $viewModel.selectedBuoy, onDismiss: {
            viewModel.clearSelection()
        }) { buoy in
            StationDetailView(station: buoy, service: viewModel.dataService)
        }
        .sheet(item: $viewModel.activeStationForGraph, onDismiss: {
            viewModel.dismissGraph()
        }) { station in
            StationDetailView(station: station, service: viewModel.dataService)
        }
        .alert("Set Home Location?", isPresented: $viewModel.showHomePrompt) {
            Button("Not Now", role: .cancel) {
                viewModel.declineHomePrompt()
            }
            Button("Set Home") {
                viewModel.confirmHomeLocation()
            }
        } message: {
            Text("Use your current location so we can surface nearby buoy and wind conditions on launch.")
        }
        .overlay(alignment: .bottom) {
            if viewModel.isTimelapseActive {
                TimelapseControlView(
                    progress: $viewModel.timelapseProgress,
                    currentDate: viewModel.timelapseCurrentDate,
                    loadingProgress: viewModel.timelapseLoadingProgress,
                    onClose: { viewModel.toggleTimelapseMode() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    ContentView()
}
