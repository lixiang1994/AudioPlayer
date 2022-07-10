//
//  AudioPlayerView.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit
import Loading
import UIImageColors

class AudioPlayerView: UIView {

    /// 标题
    @IBOutlet weak var titleLabel: UILabel!
    /// 作者
    @IBOutlet weak var authorLabel: UILabel!
    /// 背景
    @IBOutlet weak var backgroundImageView: UIImageView!
    
    /// 黑胶唱片
    @IBOutlet weak var discImageView: UIImageView!
    /// 封面
    @IBOutlet weak var coverImageView: UIImageView!
    /// 动画
    @IBOutlet weak var coverAnmiationView: UIView!
    /// 当前时间
    @IBOutlet weak var currentTimeLabel: UILabel!
    /// 时长时间
    @IBOutlet weak var durationTimeLabel: UILabel!
    /// 播放/暂停按钮
    @IBOutlet weak var playButton: UIButton!
    /// 上一曲
    @IBOutlet weak var prevButton: UIButton!
    /// 下一曲
    @IBOutlet weak var nextButton: UIButton!
    /// 播放模式
    @IBOutlet weak var modeButton: UIButton!
    /// 缓冲进度条
    @IBOutlet weak var bufferProgressView: UIProgressView!
    /// 播放进度条
    @IBOutlet weak var slider: UISlider!
    
    private lazy var planetLayer = PlanetLayer()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        setup()
    }
    
    private func setup() {
        coverAnmiationView.layer.addSublayer(planetLayer)
        // 设置等宽字体
        currentTimeLabel.font = currentTimeLabel.font.monospaced
        durationTimeLabel.font = durationTimeLabel.font.monospaced
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        planetLayer.frame = coverAnmiationView.bounds
    }
}

extension AudioPlayerView {
    
    func startAnmiation() {
        layoutIfNeeded()
        planetLayer.setupAnimation()
        addCoverImageAnmiation()
    }
    
    func set(cover: String?) {
        backgroundImageView.image = .init(named: "audio_player_bg")
        coverImageView.image = .init(named: "audio_player_cover")
        coverImageView.image?.getColors { [weak self] colors in
            self?.planetLayer.color = colors?.detail
        }
        
//        backgroundImageView.kf.setImage(with: cover, placeholder: #imageLiteral(resourceName: "audio_player_bg"), options: [.transitionFade])
//
//        coverImageView.kf.setImage(with: cover, options: [.transitionFade], completionHandler: {
//            [weak self] (result) in
//            guard let self = self else { return }
//            switch result {
//            case .success(let value):
//                value.image.getColors { colors in
//                    self.planetLayer.color = colors?.background
//                }
//            case .failure:
//                break
//            }
//        })
    }
    
    func set(title: String?, author: String?) {
        titleLabel.text = title
        authorLabel.text = author
    }
    
    func set(switchable state: (Bool, Bool)) {
        prevButton.isEnabled = state.0
        nextButton.isEnabled = state.1
    }
    
    func set(current time: TimeInterval) {
        currentTimeLabel.text = time.toHMS
        slider.value = .init(time)
    }
    
    func set(duration time: TimeInterval) {
        durationTimeLabel.text = time.toHMS
        slider.maximumValue = .init(time)
    }
    
    func set(buffer progress: Double) {
        bufferProgressView.progress = .init(progress)
    }
    
    private func addCoverImageAnmiation() {
        let animation = CABasicAnimation(keyPath: "transform.rotation")
        animation.toValue = 2.0 * .pi
        animation.repeatCount = .infinity
        animation.duration = 4
        animation.isRemovedOnCompletion = false
        discImageView.layer.add(animation, forKey: "disc")
    }
    
    func pauseAnimation() {
        discImageView.layer.pauseAnimation()
        planetLayer.pauseAnimation()
    }
    
    func resumeAnimation() {
        discImageView.layer.resumeAnimation()
        planetLayer.resumeAnimation()
    }
    
    /// 切换播放模式
    /// - Parameter mode: 播放模式
    func set(playbackMode: AudioPlayerManager.PlaybackMode) {
        switch playbackMode {
        case .sequential:
            modeButton.setImage(.init(named: "audio_player_loop"), for: .normal)
            
        case .single:
            modeButton.setImage(.init(named: "audio_player_one"), for: .normal)
            
        default:
            break
        }
    }
}

fileprivate extension UIImage {
    
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1), scale: CGFloat = 1) {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }

        color.setFill()
        UIRectFill(.init(origin: .zero, size: size))

        guard let result = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            return nil
        }
        self.init(cgImage: result)
    }
    
    func withRoundedCorners(radius: CGFloat? = nil) -> UIImage? {
        let maxRadius = min(size.width, size.height) / 2
        let cornerRadius: CGFloat
        if let radius = radius, radius > 0 && radius <= maxRadius {
            cornerRadius = radius
            
        } else {
            cornerRadius = maxRadius
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)

        let rect = CGRect(origin: .zero, size: size)
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        draw(in: rect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

extension TimeInterval {
    
    private static let format = DateFormatter()
    
    /// 01:00:00 或 12:20
    var toHMS: String {
        let format = Double.format
        format.timeZone = TimeZone(secondsFromGMT: 0)
        if self / 3600 >= 1 {
            format.dateFormat = "HH:mm:ss"
            
        } else {
            format.dateFormat = "mm:ss"
        }
        let date = Date(timeIntervalSince1970: self)
        let string = format.string(from: date)
        return string
    }
    
    /// 00:12:20
    var toHHMMSS: String {
        let format = Double.format
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "HH:mm:ss"
        let date = Date(timeIntervalSince1970: self)
        let string = format.string(from: date)
        return string
    }
}

fileprivate extension CALayer {
    
    /// 暂停动画
    func pauseAnimation() {
        //取出当前时间,转成动画暂停的时间
        let pausedTime = convertTime(CACurrentMediaTime(), from: nil)
        //设置动画运行速度为0
        speed = 0.0;
        //设置动画的时间偏移量，指定时间偏移量的目的是让动画定格在该时间点的位置
        timeOffset = pausedTime
    }
    /// 恢复动画
    func resumeAnimation() {
        //获取暂停的时间差
        let pausedTime = timeOffset
        speed = 1.0
        timeOffset = 0.0
        beginTime = 0.0
        //用现在的时间减去时间差,就是之前暂停的时间,从之前暂停的时间开始动画
        let timeSincePause = convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        beginTime = timeSincePause
    }
}

private extension UIFont {
    
    /// 等宽字体
    var monospaced: UIFont {
        let setting: [UIFontDescriptor.FeatureKey: Any]
        if #available(iOS 15.0, *) {
            setting = [
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]
            
        } else {
            setting = [
                UIFontDescriptor.FeatureKey.featureIdentifier: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.typeIdentifier: kMonospacedNumbersSelector
            ]
        }
        let new = fontDescriptor.addingAttributes([.featureSettings: [setting]])
        return UIFont(descriptor: new, size: 0)
    }
}
