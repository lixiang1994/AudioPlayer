//
//  AudioPlayerQueueController.swift
//  Demo
//
//  Created by 李响 on 2022/9/27.
//

import UIKit

class AudioPlayerQueueController: UIViewController {
    
    private let manager = AudioPlayerManager.shared
    
    @IBOutlet weak var container: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager.add(delegate: self)
        
        container.layer.cornerRadius = 10
        container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.reloadData()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard touches.first?.view == view else { return }
        hide(true)
    }
    
    static func instance() -> Self {
        return Storyboard.main.instance()
    }
}

extension AudioPlayerQueueController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return manager.queue.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = manager.queue.item(at: indexPath.row)
        cell.textLabel?.text = item?.title ?? ""
        cell.detailTextLabel?.text =  manager.item == item ? "播放中" : item?.state?.description ?? ""
        cell.detailTextLabel?.textColor = manager.item == item ? .red : .lightGray
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = manager.queue.item(at: indexPath.row) else { return }
        
        if manager.item != item {
            manager.play(item, for: manager.queue)
        }
    }
}

extension AudioPlayerQueueController: AudioPlayerManagerDelegate {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed queue: AudioPlayerQueue) {
        tableView.reloadData()
    }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?) {
        tableView.reloadData()
    }
}

fileprivate extension AudioPlayerItem.State {
 
    var description: String {
        switch self {
        case .record(let time):
            return "已播放至: \(time.toHMS)"
            
        case .played:
            return "播放完成"
            
        case .failed:
            return "播放失败"
        }
    }
}

extension AudioPlayerQueueController {
    
    func show(in parent: UIViewController, animated: Bool, completion: @escaping (() -> Void) = {}) {
        parent.addChild(self)
        parent.view.addSubview(view)
        didMove(toParent: parent)
        view.fillToSuperview()
        
        if animated {
            showAnimation(completion: completion)
        } else {
            completion()
        }
    }
    
    func hide(_ animated: Bool, completion: @escaping (() -> Void) = {}) {
        if animated {
            hideAnimation { [weak self] in
                defer { completion() }
                guard let self = self else { return }
                self.willMove(toParent: nil)
                self.view.removeFromSuperview()
                self.removeFromParent()
            }
        } else {
            defer { completion() }
            willMove(toParent: nil)
            view.removeFromSuperview()
            removeFromParent()
        }
    }
    
    /// 显示动画
    private func showAnimation(completion: @escaping () -> Void) {
        view.alpha = 0.0
        container.transform = .init(translationX: 0, y: container.bounds.height)
        
        UIView.animate(
            withDuration: 0.2,
            animations: { [weak self] in
                guard let self = self else { return }
                self.view.alpha = 1.0
                self.container.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }
    /// 隐藏动画
    private func hideAnimation(completion: @escaping () -> Void) {
        view.endEditing(true)
        view.alpha = 1.0
        container.transform = .identity
        
        UIView.animate(
            withDuration: 0.2,
            animations: { [weak self] in
                guard let self = self else { return }
                self.view.alpha = 0.0
                self.container.transform = .init(translationX: 0, y: self.container.bounds.height)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

fileprivate extension UIView {
    
    func fillToSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        if let superview = superview {
            let left = leftAnchor.constraint(equalTo: superview.leftAnchor)
            let right = rightAnchor.constraint(equalTo: superview.rightAnchor)
            let top = topAnchor.constraint(equalTo: superview.topAnchor)
            let bottom = bottomAnchor.constraint(equalTo: superview.bottomAnchor)
            NSLayoutConstraint.activate([left, right, top, bottom])
        }
    }
}
