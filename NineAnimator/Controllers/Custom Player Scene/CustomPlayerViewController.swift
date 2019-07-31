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
    
    private var playerItemStatusObservation: NSKeyValueObservation?
    
    @IBOutlet private weak var playerView: PlayerView!
    
    // Control UI
    @IBOutlet private weak var playButton: UIButton!
    
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
    
    private func play() {
        player.play()
        
        // Reflect UI
        playButton.setTitle("Pause", for: .normal)
    }
    
    private func pause() {
        player.pause()
        
        // Reflect UI
        playButton.setTitle("Play", for: .normal)
    }
    
    // TODO: Make possible UI states explicit -- paused, buffering, etc
    
    // MARK: - UI Actions
    @IBAction private func playTapped(sender: UIButton) {
        if player.timeControlStatus == .playing {
            pause()
        } else if player.timeControlStatus == .paused {
            play()
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            // TODO: Handle this
            // not sure what's best here
            // probably pause or track whether user previously hit play/pause
            print("Play tapped while waiting to play")
        }
    }
    
    // MARK: - Observing
    
    private func addPlayerItemObservers(_ playerItem: AVPlayerItem) {
        observeStatus(playerItem)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemPlaybackStalled(_:)),
                                               name: .AVPlayerItemPlaybackStalled,
                                               object: playerItem)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToEndTime(_:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: playerItem)
    }
    
    // Call before creating player with playerItem
    private func observeStatus(_ item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, changeHandler: { [weak self] (item, _) in
            switch item.status {
            case .readyToPlay:
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if item.duration.isValid && !item.duration.isIndefinite {
                        // Update total time label
                        print("Total time: \(item.duration)")
                    }
                }
            case .failed:
                print("Failed to load item")
                if let error = item.error {
                    print(error)
                }
            case .unknown:
                // Not ready to play
                // Dim UI?
                print("State unknown")
            @unknown default:
                print("Undocumented status")
            }
        })
    }
    
    private func addPlayerObservers(_ player: AVPlayer) {
        //
    }
    
    // MARK: - Notifications
    
    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        // Buffering
        DispatchQueue.main.async { [weak self] in
            // TODO: Show spinner
            print("Playback stalled")
        }
    }
    
    @objc func playerItemDidPlayToEndTime(_ notification: Notification) {
        print("Finished playing")
        pause()
    }
}
