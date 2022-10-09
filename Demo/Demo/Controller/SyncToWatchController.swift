//
//  SyncToWatchController.swift
//  Demo
//
//  Created by 李响 on 2022/9/29.
//

import UIKit

class SyncToWatchController: UIViewController {
    
    private var ids: [String] = SyncToWatch.shared.ids
    
    @IBOutlet weak var container: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 创建模拟数据 假设这两个已经下载到了本地
        var items: [AudioPlayerItem] = []
        if let item = AudioPlayerList.item(for: "1005"),
           let file = Bundle.main.url(forResource: "夜曲-周杰伦", withExtension: "wav") {
            
            let target = AudioFiles.directory.appendingPathComponent(
                "\(item.id).\(file.pathExtension)"
            )
            
            do {
                // 将文件从工程目录复制到指定沙盒目录
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: file, to: target)
                }
                // 添加音频文件记录
                AudioFiles.remove(at: item.id)
                AudioFiles.append(.init(id: item.id, pathExtension: file.pathExtension))
                // 添加到数组
                items.append(item)
                
            } catch {
                print(error)
            }
        }
        
        if let item = AudioPlayerList.item(for: "2003"),
           let file = Bundle.main.url(forResource: "江南-林俊杰", withExtension: "wav") {
            
            let target = AudioFiles.directory.appendingPathComponent(
                "\(item.id).\(file.pathExtension)"
            )
            
            do {
                // 将文件从工程目录复制到指定沙盒目录
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: file, to: target)
                }
                // 添加音频文件记录
                AudioFiles.remove(at: item.id)
                AudioFiles.append(.init(id: item.id, pathExtension: file.pathExtension))
                // 添加到数组
                items.append(item)
                
            } catch {
                print(error)
            }
        }
        ids = items.map({ $0.id })
        
        container.layer.cornerRadius = 10
        container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        NotificationCenter.default.addObserver(
            forName: SyncToWatch.stateChanged,
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            self.tableView.reloadData()
        }
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
    
    @IBAction func syncAction(_ sender: UIButton) {
        
        if !WatchSession.isWatchAppInstalled {
            let alert = UIAlertController(
                title: "未安装手表应用",
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(.init(title: "好的", style: .cancel))
            present(alert, animated: true)
            return
        }
        
        if !WatchSession.isPaired {
            let alert = UIAlertController(
                title: "设备未配对",
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(.init(title: "好的", style: .cancel))
            present(alert, animated: true)
            return
        }
        
        if !WatchSession.isReachable {
            let alert = UIAlertController(
                title: "不可访问 请打开手表应用",
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(.init(title: "好的", style: .cancel))
            present(alert, animated: true)
            return
        }
        
        SyncToWatch.shared.sync(ids) { [weak self] result in
            guard let self = self else { return }
            if result {
                let alert = UIAlertController(
                    title: "已开始同步",
                    message: "请确保手表与手机的连接",
                    preferredStyle: .alert
                )
                alert.addAction(.init(title: "好的", style: .cancel))
                self.present(alert, animated: true)
                self.tableView.reloadData()
                
            } else {
                let alert = UIAlertController(
                    title: "同步失败 稍后再试",
                    message: "请确保手表与手机的连接",
                    preferredStyle: .alert
                )
                alert.addAction(.init(title: "好的", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }
    
    static func instance() -> Self {
        return Storyboard.main.instance()
    }
}

extension SyncToWatchController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ids.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let id = ids[indexPath.row]
        let item = AudioPlayerList.item(for: id)
        cell.textLabel?.text = item?.title ?? ""
        cell.detailTextLabel?.text = SyncToWatch.shared.state(for: id)?.description
        return cell
    }
}

fileprivate extension SyncToWatch.State {
    
    var description: String {
        switch self {
        case .sending:
            return "发送中"
            
        case .finished:
            return "发送完成"
            
        case .failed:
            return "发送失败"
        }
    }
}

extension SyncToWatchController {
    
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
