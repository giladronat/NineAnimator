//
//  CustomPlayerViewController.swift
//  NineAnimator
//
//  Created by Gilad Ronat on 7/31/19.
//  Copyright © 2019 Marcus Zhou. All rights reserved.
//

import AVFoundation
import UIKit

// swiftlint:disable todo
class CustomPlayerViewController: UIViewController {
    private var media: PlaybackMedia?
    private var playerItem: AVPlayerItem?
    
    private let player = AVPlayer()
    
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var playerItemIsPlaybackLikelyToKeepUpObservation: NSKeyValueObservation?
    private var playerItemIsPlaybackBufferEmptyObservation: NSKeyValueObservation?
    private var playerItemIsPlaybackBufferFullObservation: NSKeyValueObservation?
    
    @IBOutlet private weak var playerLayerView: PlayerLayerView!
    
    // Control UI
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet private weak var currentPlaybackTimeLabel: UILabel!
    @IBOutlet private weak var timeToEndLabel: UILabel!
    @IBOutlet private weak var totalTimeLabel: UILabel!
    
    func play(_ media: PlaybackMedia) {
        self.media = media
        play(media.avPlayerItem)
    }
    
    private func play(_ playerItem: AVPlayerItem) {
        self.playerItem = playerItem
        preparePlayer()
        play()
    }
    
    private func preparePlayer() {
        // Set up view layer
        playerLayerView.player = player
        
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
        playerItemStatusObservation = observeStatus(playerItem)
        playerItemIsPlaybackLikelyToKeepUpObservation = observeIsPlaybackLikelyToKeepUp(playerItem)
        playerItemIsPlaybackBufferEmptyObservation = observeIsPlaybackBufferEmpty(playerItem)
        playerItemIsPlaybackBufferFullObservation = observeIsPlaybackBufferFull(playerItem)
        
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
    private func observeStatus(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.status) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if item.duration.isValid && !item.duration.isIndefinite {
                        // Update total time label
                        let totalTimeSeconds = TimeInterval(item.duration.seconds)
                        self.totalTimeLabel.text = self.format(timeInterval: totalTimeSeconds)
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
        }
    }
    
    // TODO: Find where to call this
    private func removePlayerItemObservers(_ playerItem: AVPlayerItem) {
        playerItemStatusObservation = nil
        playerItemIsPlaybackBufferFullObservation = nil
        playerItemIsPlaybackBufferEmptyObservation = nil
        playerItemIsPlaybackLikelyToKeepUpObservation = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }
    
    private func addPlayerObservers(_ player: AVPlayer) {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] time in
            guard let item = self?.playerItem, let self = self else { return }
            
            // Update UI
            // TODO: Extract this
            let currentPlaybackSeconds = TimeInterval(time.seconds)
            let timeToEndSeconds = TimeInterval(item.duration.seconds - time.seconds)
            let currentPlaybackString = self.format(timeInterval: currentPlaybackSeconds)
            let timeToEndString = "-\(self.format(timeInterval: timeToEndSeconds))"
            
            self.currentPlaybackTimeLabel.text = currentPlaybackString
            self.timeToEndLabel.text = timeToEndString
        }
    }
    
    // TODO: Find where to call this
    private func removePlayerObservers() {
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
    
    // MARK: - Notifications
    
    @objc func playerItemDidPlayToEndTime(_ notification: Notification) {
        Log.debug("Finished playing")
        pause()
    }
}

// MARK: - Buffering

extension CustomPlayerViewController {
    // Buffering:
    // playerItem.isPlaybackBufferEmpty
    // player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    // PlaybackStalled notification
    
    // Not Buffering:
    // playerItem.isPlaybackLikelyToKeepUp
    // playerItem.isPlaybackBufferFull
    // playerItem.status == .readyToPlay
    
    // Does playback automatically pause while buffering?
    
    private func observeIsPlaybackLikelyToKeepUp(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            let isLikelyString = "Likely to keep up: \(item.isPlaybackLikelyToKeepUp)"
            Log.debug("%@", isLikelyString)
        }
    }
    
    private func observeIsPlaybackBufferEmpty(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
            Log.debug("Buffer empty: %@", item.isPlaybackBufferEmpty)
        }
    }
    
    private func observeIsPlaybackBufferFull(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.isPlaybackBufferFull) { [weak self] item, _ in
            Log.debug("Buffer full: %@", item.isPlaybackBufferFull)
        }
    }
    
    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        // Buffering
        DispatchQueue.main.async { [weak self] in
            // TODO: Show spinner
            Log.debug("Playback stalled")
        }
    }
}

// MARK: - Date Formatting Helpers

// TODO: Check if I should keep these, if so extract to Utilities
extension DateFormatter {
    static let playerTimeDateFormatter: DateFormatter = {
        let timeFormat = "mm:ss"
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = timeFormat
        
        return formatter
    }()
}

extension CustomPlayerViewController {
    private func format(timeInterval: TimeInterval) -> String {
        var timeFormat: String = "mm:ss"
        if timeInterval >= 3600 {
            timeFormat = "HH:mm:ss"
        }
        let date = Date(timeIntervalSince1970: timeInterval)
        let formatter = DateFormatter.playerTimeDateFormatter
        formatter.dateFormat = timeFormat
        
        return formatter.string(from: date)
    }
}

// MARK: - Test Preview

extension CustomPlayerViewController {
    override func viewWillAppear(_ animated: Bool) {
        let m3u8TestPlayerItem = AVPlayerItem(url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!)
        let mp4TestPlayerItem = AVPlayerItem(url: URL(string: "https://sample-videos.com/video123/mp4/720/big_buck_bunny_720p_2mb.mp4")!)
        play(mp4TestPlayerItem)
        
        super.viewWillAppear(animated)
    }
}
