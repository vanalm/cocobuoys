//
//  StationAnnotationView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import MapKit
import SwiftUI

final class StationAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "StationAnnotationView"
    
    private let markerLayer = CAShapeLayer()
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    override var annotation: MKAnnotation? {
        didSet {
            applyCurrentStyle()
        }
    }

    func refreshStyle() {
        applyCurrentStyle()
    }
    
    private func setup() {
        canShowCallout = false
        markerLayer.fillColor = UIColor.systemBlue.cgColor
        markerLayer.opacity = 0.9
        layer.addSublayer(markerLayer)
    }
    
    private func trianglePath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.close()
        return path.cgPath
    }
    
    private func applyCurrentStyle() {
        guard let stationAnnotation = annotation as? StationAnnotation else {
            return
        }

        if case let .wave(style) = stationAnnotation.kind {
            apply(style: style)
        } else {
            apply(style: BuoyMarkerStyle(color: .blue, opacity: 0.9, size: 18, direction: 0))
        }
    }
    
    private func apply(style: BuoyMarkerStyle) {
        let width = style.size
        let height = style.size * 1.4
        bounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        markerLayer.frame = bounds
        markerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        markerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        markerLayer.path = trianglePath(width: width, height: height)
        markerLayer.fillColor = UIColor(style.color).cgColor
        markerLayer.opacity = Float(style.opacity)
        
        markerLayer.setAffineTransform(.identity)
        let adjustedDirection = (style.direction + 180).truncatingRemainder(dividingBy: 360)
        let radians = CGFloat(adjustedDirection) * .pi / 180
        markerLayer.setAffineTransform(CGAffineTransform(rotationAngle: radians))
        
        centerOffset = .zero
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let inset: CGFloat = -16
        return bounds.insetBy(dx: inset, dy: inset).contains(point)
    }
}
