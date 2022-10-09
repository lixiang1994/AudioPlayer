//
//  ViewController.swift
//  Demo
//
//  Created by 李响 on 2022/7/7.
//

import UIKit

protocol ViewControllerable: UIViewController {
    associatedtype Container: UIView
    
    var container: Container { get }
}

extension ViewControllerable {
    
    var container: Container { view as! Container }
}

class ViewController<Container: UIView>: UIViewController, ViewControllerable {
    
    override func loadView() {
        // storyboard 初始化
        super.loadView()
        if view is Container {
            return
        }
        // 纯代码初始化
        view = Container()
    }
    
    override init(nibName nibNameOrNil: String? = .none, bundle nibBundleOrNil: Bundle? = .none) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
//    static func instance() -> Self {
//        return Self()
//    }
    
    deinit { print("deinit:", classForCoder) }
}
