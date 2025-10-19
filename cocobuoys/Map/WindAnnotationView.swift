//
//  WindAnnotationView.swift
//  cocobuoys
//
//  Created by Codex on 10/17/25.
//

import MapKit
import SwiftUI
import UIKit

final class WindAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "WindAnnotationView"
    
    private let containerLayer = CALayer()
    private let shaftLayer = CAShapeLayer()
    private let headLayer = CAShapeLayer()
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override var annotation: MKAnnotation? {
        didSet {
            applyCurrentStyle()
        }
    }
    
    private func setup() {
        canShowCallout = false
        backgroundColor = .clear
        shaftLayer.lineWidth = 2
        shaftLayer.lineCap = .round
        shaftLayer.fillColor = UIColor.clear.cgColor
        containerLayer.addSublayer(shaftLayer)
        headLayer.fillColor = UIColor.label.cgColor
        headLayer.strokeColor = UIColor.clear.cgColor
        containerLayer.addSublayer(headLayer)
        layer.addSublayer(containerLayer)
    }
    
    private func applyCurrentStyle() {
        guard let stationAnnotation = annotation as? StationAnnotation,
              case let .wind(style) = stationAnnotation.kind else {
            return
        }
        apply(style: style)
    }
    
    private func apply(style: WindMarkerStyle) {
        let baseLength: CGFloat = 28
        let speed = CGFloat(style.speedKnots ?? 0)
        let clampedSpeed = min(max(speed, 5), 40)
        let length = baseLength + (clampedSpeed - 5) * 1.2
        let width: CGFloat = 12
        let size = CGSize(width: width, height: length)
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = .zero
        
        shaftLayer.strokeColor = UIColor(style.color).cgColor
        headLayer.fillColor = UIColor(style.color).cgColor
        
        containerLayer.bounds = bounds
        containerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        containerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        containerLayer.setAffineTransform(.identity)
        
        let shaftPath = UIBezierPath()
        shaftPath.move(to: CGPoint(x: bounds.midX, y: bounds.maxY))
        shaftPath.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY + 8))
        shaftLayer.path = shaftPath.cgPath
        shaftLayer.frame = bounds
        
        let arrowHead = UIBezierPath()
        arrowHead.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        arrowHead.addLine(to: CGPoint(x: bounds.midX - 6, y: bounds.minY + 10))
        arrowHead.addLine(to: CGPoint(x: bounds.midX + 6, y: bounds.minY + 10))
        arrowHead.close()
        headLayer.path = arrowHead.cgPath
        headLayer.frame = bounds
        
        let adjustedDirection = ((style.direction ?? 0) + 180).truncatingRemainder(dividingBy: 360)
        let rotation = CGFloat(adjustedDirection * .pi / 180)
        containerLayer.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let inset: CGFloat = -16
        return bounds.insetBy(dx: inset, dy: inset).contains(point)
    }
}
