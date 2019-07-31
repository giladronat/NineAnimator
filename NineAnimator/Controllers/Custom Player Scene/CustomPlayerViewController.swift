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
    private var media: PlaybackMedia?
    private var playerItem: AVPlayerItem? {
        return media?.avPlayerItem
    }
    
    private let player = AVPlayer()
    
    @IBOutlet private weak var playerView: PlayerView!
    
    func play(_ media: PlaybackMedia) {
        self.media = media
        preparePlayer()
        play()
    }
    
    private func preparePlayer() {
        // Set up view layer
        playerView.player = player
        
        if let playerItem = playerItem {
            addPlayerItemObservers(playerItem)
        }
        addPlayerObservers(player)
        
        // Set up player with item
        player.replaceCurrentItem(with: playerItem)
    }
    
    private func addPlayerItemObservers(_ playerItem: AVPlayerItem) {
        //
    }
    
    private func addPlayerObservers(_ player: AVPlayer) {
        //
    }
    
    private func play() {
        player.play()
    }
    
    private func pause() {
        player.pause()
    }
}
