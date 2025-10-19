//
//  SatelliteMapView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import Foundation
import MapKit
import SwiftUI

struct SatelliteMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion?
    var annotations: [StationAnnotation]
    var showsUserLocation: Bool
    var mapStyle: MapBaseLayer = .hybrid
    var onSelectStation: (MarineStation) -> Void = { _ in }
    var onDeselectStation: () -> Void = {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(region: $region, onSelectStation: onSelectStation, onDeselectStation: onDeselectStation)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = showsUserLocation
        mapView.register(StationAnnotationView.self, forAnnotationViewWithReuseIdentifier: StationAnnotationView.reuseIdentifier)
        mapView.register(WindAnnotationView.self, forAnnotationViewWithReuseIdentifier: WindAnnotationView.reuseIdentifier)
        context.coordinator.apply(style: mapStyle, on: mapView)
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.showsUserLocation = showsUserLocation
        context.coordinator.apply(style: mapStyle, on: uiView)
        
        if let region = region {
            context.coordinator.setRegion(region, on: uiView)
        }
        
        context.coordinator.syncAnnotations(annotations, on: uiView)
    }
}

extension SatelliteMapView {
    final class Coordinator: NSObject, MKMapViewDelegate {
        @Binding private var region: MKCoordinateRegion?
        private var currentAnnotations: [StationAnnotation] = []
        private let onSelectStation: (MarineStation) -> Void
        private let onDeselectStation: () -> Void
        private var tileOverlay: MKTileOverlay?
        private var currentStyle: MapBaseLayer?
        
        init(region: Binding<MKCoordinateRegion?>, onSelectStation: @escaping (MarineStation) -> Void, onDeselectStation: @escaping () -> Void) {
            self._region = region
            self.onSelectStation = onSelectStation
            self.onDeselectStation = onDeselectStation
        }
        
        func apply(style: MapBaseLayer, on mapView: MKMapView) {
            guard style != currentStyle else { return }
            currentStyle = style
            switch style {
            case .hybrid:
                removeTileOverlay(from: mapView)
                if #available(iOS 16.0, *) {
                    mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
                }
                mapView.mapType = .hybrid
            case .street:
                addTileOverlay(to: mapView)
                if #available(iOS 16.0, *) {
                    mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
                }
                mapView.mapType = .standard
            }
        }
        
        private func addTileOverlay(to mapView: MKMapView) {
            if tileOverlay == nil {
                let overlay = MKTileOverlay(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
                overlay.canReplaceMapContent = true
                tileOverlay = overlay
            }
            if let overlay = tileOverlay, !mapView.overlays.contains(where: { $0 === overlay }) {
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
        }
        
        private func removeTileOverlay(from mapView: MKMapView) {
            if let overlay = tileOverlay, mapView.overlays.contains(where: { $0 === overlay }) {
                mapView.removeOverlay(overlay)
            }
        }
        
        func setRegion(_ target: MKCoordinateRegion, on mapView: MKMapView) {
            guard mapView.region.center.latitude.isFinite else {
                mapView.setRegion(target, animated: false)
                return
            }
            
            let delta = abs(mapView.region.center.latitude - target.center.latitude)
            if delta > 0.01 {
                mapView.setRegion(target, animated: true)
            }
        }
        
        func syncAnnotations(_ annotations: [StationAnnotation], on mapView: MKMapView) {
            let toRemove = currentAnnotations.filter { current in
                !annotations.contains(where: { $0.identifier == current.identifier })
            }
            let toAdd = annotations.filter { incoming in
                !currentAnnotations.contains(where: { $0.identifier == incoming.identifier })
            }
            
            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }
            
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }
            
            currentAnnotations = annotations
        }
        
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            region = mapView.region
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stationAnnotation = annotation as? StationAnnotation else {
                return nil
            }
            switch stationAnnotation.kind {
            case .wave:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: StationAnnotationView.reuseIdentifier,
                    for: stationAnnotation
                )
                view.annotation = stationAnnotation
                return view
            case .wind:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: WindAnnotationView.reuseIdentifier,
                    for: stationAnnotation
                )
                view.annotation = stationAnnotation
                return view
            }
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let stationAnnotation = view.annotation as? StationAnnotation else { return }
            DispatchQueue.main.async {
                self.onSelectStation(stationAnnotation.station)
            }
        }
        
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard view.annotation as? StationAnnotation != nil else { return }
            DispatchQueue.main.async {
                self.onDeselectStation()
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
