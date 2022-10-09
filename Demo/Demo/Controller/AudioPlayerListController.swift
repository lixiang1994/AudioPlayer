//
//  AudioPlayerListController.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit

class AudioPlayerListController: UIViewController {
    
    private let manager = AudioPlayerManager.shared
    
    private var group: [[AudioPlayerItem]] = []
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
        loadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.reloadData()
    }
    
    @IBAction func syncToWatchAction(_ sender: UIBarButtonItem) {
        let controller = SyncToWatchController.instance()
        controller.show(in: self, animated: true)
    }
    
    @IBAction func clearQueueAction(_ sender: UIBarButtonItem) {
        manager.clear()
    }
}

extension AudioPlayerListController {
    
    private func setup() {
        tableView.contentInset = .init(top: 40, left: 0, bottom: 0, right: 0)
        // 添加代理
        manager.add(delegate: self)
    }
    
    private func loadData() {
        var group: [String: [AudioPlayerItem]] = [:]
        for item in AudioPlayerList.items {
            var temp = group[item.author] ?? []
            temp.append(item)
            group[item.author] = temp
        }
        self.group = .init(group.values)
        self.tableView.reloadData()
    }
}

extension AudioPlayerListController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return group.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return group[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = group[indexPath.section][indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text =  manager.item == item ? "播放中" : item.state?.description ?? ""
        cell.detailTextLabel?.textColor = manager.item == item ? .red : .lightGray
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let items = group[indexPath.section]
        let item = items[indexPath.row]
        
        if manager.item != item {
            manager.play(item, for: .init(items))
        }
        
        // 打开播放器页面
        let controller = AudioPlayerController.instance()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return group[section].first?.author ?? ""
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
