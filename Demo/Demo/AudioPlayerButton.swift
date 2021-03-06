//
//  AudioPlayerButton.swift
//  Demo
//
//  Created by 李响 on 2022/7/14.
//

import UIKit

class AudioPlayerButton: UIButton {
    
    private lazy var shape: CAShapeLayer = {
        $0.strokeColor = UIColor.white.cgColor
        $0.fillColor = UIColor.clear.cgColor
        $0.lineWidth = 2
        $0.lineCap = CAShapeLayerLineCap.round
        $0.bounds = .init(x: 0, y: 0, width: 50, height: 50)
        return $0
    } ( CAShapeLayer() )
    
    private var duration: TimeInterval = 1.5
    private var timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    private var isAnimating = false
    
    var isLoading: Bool {
        get { isAnimating }
        set {
            newValue ? start() : stop()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        
        layer.addSublayer(shape)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        shape.position = .init(x: bounds.midX, y: bounds.midY)
        shape.bounds = bounds
        
        let center = CGPoint(x: shape.bounds.midX, y: shape.bounds.midY)
        let radius = min(shape.bounds.midX,
                         shape.bounds.midX - shape.lineWidth / 2)
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2.0,
            clockwise: true
        )
        shape.path = path.cgPath
    }
    
    private func start() {
        isAnimating = true
        addAnimation()
    }
    
    private func stop() {
        isAnimating = false
        removeAnimation()
    }
}

extension AudioPlayerButton {
    
    /// 设置颜色
    ///
    /// - Parameter line: 颜色
    func set(line color: UIColor) {
        shape.strokeColor = color.cgColor
    }
    
    /// 设置线条宽度
    ///
    /// - Parameter line: 宽度
    func set(line width: CGFloat) {
        shape.lineWidth = width
        layoutSubviews()
    }
    
    /// 设置动画时长
    ///
    /// - Parameter duration: 时长
    func set(duration: TimeInterval) {
        self.duration = duration
        if isAnimating {
            removeAnimation()
            addAnimation()
        }
    }
    
    /// 设置动画曲线
    ///
    /// - Parameter timingFunction: 默认 EaseInEaseOut
    func set(timingFunction: CAMediaTimingFunction) {
        self.timingFunction = timingFunction
        if isAnimating {
            removeAnimation()
            addAnimation()
        }
    }
}

extension AudioPlayerButton {
    
    private func addAnimation() {
        guard shape.animation(forKey: "A") == nil else {
            return
        }
        
        let animation = CABasicAnimation()
        animation.keyPath = "transform.rotation"
        animation.fromValue = 0
        animation.toValue = .pi * 2.0
        animation.duration = duration / 0.375
        animation.repeatCount = HUGE
        animation.isRemovedOnCompletion = false
        shape.add(animation, forKey: "A")
        
        let headAnimation = CABasicAnimation()
        headAnimation.keyPath = "strokeStart"
        headAnimation.fromValue = 0
        headAnimation.toValue = 0.25
        headAnimation.duration = duration / 1.5
        headAnimation.timingFunction = timingFunction
        
        let tailAnimation = CABasicAnimation()
        tailAnimation.keyPath = "strokeEnd"
        tailAnimation.fromValue = 0
        tailAnimation.toValue = 1
        tailAnimation.duration = duration / 1.5
        tailAnimation.timingFunction = timingFunction
        
        let endHeadAnimation = CABasicAnimation()
        endHeadAnimation.keyPath = "strokeStart"
        endHeadAnimation.fromValue = 0.25
        endHeadAnimation.toValue = 1
        endHeadAnimation.beginTime = duration / 1.5
        endHeadAnimation.duration = duration / 3.0
        endHeadAnimation.timingFunction = timingFunction
        
        let endTailAnimation = CABasicAnimation()
        endTailAnimation.keyPath = "strokeEnd"
        endTailAnimation.fromValue = 1
        endTailAnimation.toValue = 1
        endTailAnimation.beginTime = duration / 1.5
        endTailAnimation.duration = duration / 3.0
        endTailAnimation.timingFunction = timingFunction
        
        let animations = CAAnimationGroup()
        animations.duration = duration
        animations.animations = [
            headAnimation,
            tailAnimation,
            endHeadAnimation,
            endTailAnimation
        ]
        animations.repeatCount = HUGE
        animations.isRemovedOnCompletion = false
        shape.add(animations, forKey: "B")
    }
    
    private func removeAnimation() {
        shape.removeAllAnimations()
    }
}
