//
//  CustomPlayerViewController.swift
//  NineAnimator
//
//  Created by Gilad Ronat on 7/31/19.
//  Copyright © 2019 Marcus Zhou. All rights reserved.
//

import AVFoundation
import UIKit

class CustomPlayerViewController: UIViewController {

    private let player = AVPlayer()
    
    @IBOutlet weak var playerView: PlayerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        preparePlayer()
    }
    
    private func preparePlayer() {
        playerView.player = player
    }

}
