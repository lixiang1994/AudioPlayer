//
//  AudioPlayerPlanetLayer.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit

class PlanetLayer: CAReplicatorLayer {

    // 波纹
    private lazy var shapeLayer = CAShapeLayer()
    // 小点
    private lazy var pointLayer = CALayer()
    // 小点轨迹
    private lazy var pointOrbitLayer = CAShapeLayer()
    
    var color: UIColor? = #colorLiteral(red: 0.6784313725, green: 0.5568627451, blue: 0.4705882353, alpha: 1) {
        didSet {
            guard let color = color else {
                return
            }
            shapeLayer.strokeColor = color.cgColor
            pointLayer.backgroundColor = color.withAlphaComponent(0.7).cgColor
        }
    }
    
    var animationDuration: TimeInterval = 6
    
    private lazy var animationGroup = CAAnimationGroup()
    
    private var center: CGPoint {
        return .init(x: bounds.height * 0.5, y: bounds.height * 0.5)
    }
    
    override init() {
        super.init()
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setupAnimation() {
        do {
            let animationGroup = CAAnimationGroup()
            animationGroup.duration = animationDuration
            animationGroup.repeatCount = .infinity
            animationGroup.timingFunction = .init(name: .linear)
            animationGroup.isRemovedOnCompletion = false
            
            let path1 = UIBezierPath(
                arcCenter: center,
                radius: 1,
                startAngle: 0,
                endAngle: 2.0 * .pi,
                clockwise: true
            )
            
            let path2 = UIBezierPath(
                arcCenter: center,
                radius: bounds.height * 0.5,
                startAngle: 0,
                endAngle: 2.0 * .pi,
                clockwise: true
            )
            
            let pathAnimation = CABasicAnimation(keyPath: "path")
            pathAnimation.fromValue = path1.cgPath
            pathAnimation.toValue = path2.cgPath
            pathAnimation.duration = animationDuration
            
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.duration = animationDuration
            opacityAnimation.values = [1, 0.9, 0.8, 0.6, 0.3, 0]
            opacityAnimation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animationGroup.animations = [pathAnimation, opacityAnimation]
            
            shapeLayer.add(animationGroup, forKey: "pulse")
        }
        
        do {
            let animationGroup = CAAnimationGroup()
            animationGroup.duration = animationDuration
            animationGroup.repeatCount = .infinity
            animationGroup.timingFunction = .init(name: .linear)
            animationGroup.isRemovedOnCompletion = false
            // 透明度
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.duration = animationDuration
            opacityAnimation.values = [1, 0.9, 0.8, 0.6, 0.3, 0]
            opacityAnimation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            
            // 放大
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.duration = animationDuration
            scaleAnimation.fromValue = 1
            scaleAnimation.toValue = 1
            
            let path = UIBezierPath(
                arcCenter: center,
                radius: bounds.height * 0.5,
                startAngle: 0,
                endAngle: 2.0 * .pi,
                clockwise: true
            )
            // 运动路径
            let pathAnimation = CAKeyframeAnimation.init(keyPath: "position")
            pathAnimation.duration = animationDuration
            pathAnimation.path = path.cgPath

            animationGroup.animations = [scaleAnimation, pathAnimation, opacityAnimation]
            pointLayer.add(animationGroup, forKey: "point")
        }
        
        do {
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.duration = animationDuration
            scaleAnimation.fromValue = 0
            scaleAnimation.toValue = 1
            scaleAnimation.repeatCount = .infinity
            scaleAnimation.timingFunction = .init(name: .linear)
            scaleAnimation.isRemovedOnCompletion = false
            pointOrbitLayer.add(scaleAnimation, forKey: "scale")
        }
    }
    
    override func layoutSublayers() {
        super.layoutSublayers()
        
        let radius1: CGFloat = bounds.width * 0.5
        let radius2: CGFloat = 4
        
        shapeLayer.frame = .init(x: 0, y: 0, width: radius1 * 2, height: radius1 * 2)
        shapeLayer.position = CGPoint(x: radius1, y: radius1)
        
        pointLayer.frame = .init(x: 0, y: 0, width: radius2 * 2, height: radius2 * 2)
        pointLayer.cornerRadius = radius2
        
        pointOrbitLayer.frame = .init(x: 0, y: 0, width: radius1 * 2, height: radius1 * 2)
        let path = UIBezierPath(
            arcCenter: center,
            radius: bounds.height * 0.5,
            startAngle: 0,
            endAngle: 2.0 * .pi,
            clockwise: true
        )
        pointOrbitLayer.path = path.cgPath
    }
    
    private func setup() {
        addSublayer(shapeLayer)
        addSublayer(pointOrbitLayer)
        pointOrbitLayer.addSublayer(pointLayer)
        
        shapeLayer.contentsScale = UIScreen.main.scale
        shapeLayer.opacity = 0
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.strokeColor = color?.cgColor
        
        pointOrbitLayer.contentsScale = UIScreen.main.scale
        pointOrbitLayer.fillColor = UIColor.clear.cgColor
        pointOrbitLayer.strokeColor = UIColor.clear.cgColor
        
        pointLayer.opacity = 0
        pointLayer.backgroundColor = color?.withAlphaComponent(0.7).cgColor
        instanceCount = 5
        instanceDelay = animationDuration / 5
        
        let angle: CGFloat = .random(in: 0...(2 * .pi))
        instanceTransform = CATransform3DMakeRotation(angle, 0, 0, 1)
    }
}

