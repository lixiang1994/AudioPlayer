//
//  AudioPlayerListController.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit

class AudioPlayerListController: UIViewController {
    
    let manager = AudioPlayerManager.shared
    
    let queue = AudioPlayerQueue(
        [
            .init(
                id: "1",
                title: "最伟大的作品",
                cover: "cover_01",
                author: "周杰伦",
                duration: 880.85,
                resource: URL(string: "https://chtbl.com/track/1F1B1F/traffic.megaphone.fm/WSJ2560705456.mp3")!
            ),
            .init(
                id: "2",
                title: "布拉格广场",
                cover: "cover_02",
                author: "蔡依林,周杰伦",
                duration: 293.90,
                resource: Bundle.main.url(forResource: "蔡依林,周杰伦 - 布拉格广场", withExtension: "mp3")!
            )
        ]
    )
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager.add(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.reloadData()
    }
}

extension AudioPlayerListController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return queue.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = queue.item(at: indexPath.row)
        cell.textLabel?.text = item?.title ?? ""
        cell.detailTextLabel?.text =  manager.item == item ? "播放中" : item?.state?.description ?? ""
        cell.detailTextLabel?.textColor = manager.item == item ? .red : .lightGray
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = queue.item(at: indexPath.row) else { return }
        
        if manager.item != item {
            manager.play(item, for: queue)
        }
        
        // 打开播放器页面
        let controller = AudioPlayerController.instance()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

extension AudioPlayerListController: AudioPlayerManagerDelegate {
    
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
