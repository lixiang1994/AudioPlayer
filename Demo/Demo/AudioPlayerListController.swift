//
//  AudioPlayerListController.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit

class AudioPlayerListController: UIViewController {
    
    let queue = AudioPlayerQueue(
        [
            .init(
                id: "1",
                title: "最伟大的作品",
                cover: "",
                author: "周杰伦",
                resource: URL(string: "https://chtbl.com/track/1F1B1F/traffic.megaphone.fm/WSJ2560705456.mp3")!
            ),
            .init(
                id: "2",
                title: "烟花易冷",
                cover: "",
                author: "周杰伦",
                resource: URL(string: "https://chtbl.com/track/1F1B1F/traffic.megaphone.fm/WSJ2560705456.mp3")!
            )
        ]
    )
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    @IBAction func openAction(_ sender: UIButton) {
        let controller = AudioPlayerController.instance()
        present(controller, animated: true)
        
        controller.play(queue.item(at: 0)!, for: queue)
    }
}
