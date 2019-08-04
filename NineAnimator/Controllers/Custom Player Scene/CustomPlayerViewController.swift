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
    private var playerItemLoadedTimeRangesObservation: NSKeyValueObservation?
    
    private var playerTimeControlStatusObservation: NSKeyValueObservation?
    
    @IBOutlet private weak var playerLayerView: PlayerLayerView!
    
    // Control UI
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet private weak var currentPlaybackTimeLabel: UILabel!
    @IBOutlet private weak var timeToEndLabel: UILabel!
    @IBOutlet private weak var totalTimeLabel: UILabel!
    
    @IBOutlet private weak var bufferSpinner: UIActivityIndicatorView!
    
    @IBOutlet private weak var playbackProgressSlider: UISlider!
    @IBOutlet private weak var playbackBufferProgressView: UIProgressView!
    
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
        
        setUpPlaybackSession()
        
        // Set up player with item
        // Important to call _after_ adding observers
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
    
    // TODO: Call somewhere. Maybe viewWillDisappear (PiP?)
    private func tearDown() {
        removePlayerObservers()
        if let item = playerItem {
            removePlayerItemObservers(item)
        }
        tearDownPlaybackSession()
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
        playerItemLoadedTimeRangesObservation = observeLoadedTimeRanges(playerItem)
        
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
                        Log.debug("Ready to play")
                        let totalTimeSeconds = TimeInterval(item.duration.seconds)
                        self.totalTimeLabel.text = self.format(timeInterval: totalTimeSeconds)
                        self.playbackProgressSlider.maximumValue = Float(totalTimeSeconds)
                    }
                }
            case .failed:
                print("Failed to load item")
                if let error = item.error {
                    print(error)
                }
            case .unknown:
                // Not ready to play
                // Preparing
                Log.debug("Item status unknown")
                self?.bufferSpinner.isHidden = false
            @unknown default:
                print("Undocumented status")
            }
        }
    }
    
    private func removePlayerItemObservers(_ playerItem: AVPlayerItem) {
        playerItemStatusObservation = nil
        playerItemIsPlaybackBufferFullObservation = nil
        playerItemIsPlaybackBufferEmptyObservation = nil
        playerItemIsPlaybackLikelyToKeepUpObservation = nil
        playerItemLoadedTimeRangesObservation = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }
    
    private func addPlayerObservers(_ player: AVPlayer) {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] time in
            guard let item = self?.playerItem, let self = self else { return }
            
            // Update UI
            // TODO: Extract this
            let currentPlaybackSeconds = time.seconds
            let timeToEndSeconds = item.duration.seconds - time.seconds
            let currentPlaybackString = self.format(timeInterval: currentPlaybackSeconds)
            let timeToEndString = "-\(self.format(timeInterval: timeToEndSeconds))"
            
            self.currentPlaybackTimeLabel.text = currentPlaybackString
            self.timeToEndLabel.text = timeToEndString
            
            self.playbackProgressSlider.setValue(Float(currentPlaybackSeconds), animated: true)
        }
        
        playerTimeControlStatusObservation = observePlayerTimeControlStatus(player)
    }
    
    private func removePlayerObservers() {
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        playerTimeControlStatusObservation = nil
    }
    
    // MARK: - Notifications
    
    @objc private func playerItemDidPlayToEndTime(_ notification: Notification) {
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
    
    // Does playback automatically pause while buffering?
    
    private func observeIsPlaybackLikelyToKeepUp(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            if item.isPlaybackLikelyToKeepUp {
                // Likely playing, not stuck buffering
                self?.bufferSpinner.isHidden = true
                Log.debug("Keeping up")
            } else {
                // Stuck buffering
                self?.bufferSpinner.isHidden = false
                Log.debug("Not keeping up")
            }
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
    
    private func observePlayerTimeControlStatus(_ player: AVPlayer) -> NSKeyValueObservation {
        return player.observe(\AVPlayer.timeControlStatus) { [weak self] player, _ in
            switch player.timeControlStatus {
            case .paused:
                // Could waitingToPlay happen while video appears paused?
                // I think no need to touch spinner
                if !(self?.playerItem?.isPlaybackLikelyToKeepUp ?? true) {
                    Log.debug("Player paused and unlikely to keep up (buffering)")
                }
            case .playing:
                Log.debug("Status: playing (not buffering)")
                self?.bufferSpinner.isHidden = true
            case .waitingToPlayAtSpecifiedRate:
                // Waiting Reason is often "evaluatingBufferingRate" -- not buffering
                if let reason = player.reasonForWaitingToPlay, reason == .toMinimizeStalls {
                    // Waiting for the buffer
                    Log.debug("Waiting to minimize stalls")
                    self?.bufferSpinner.isHidden = false
                }
                
            @unknown default:
                print("Undocumented time control status: \(player.timeControlStatus)")
            }
        }
    }
    
    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        // ???: Do notifications get called on the same thread they're registered in?
        if !Thread.isMainThread {
            print("Stalled notification received on other thread")
        }
        // Buffering
        DispatchQueue.main.async { [weak self] in
            self?.bufferSpinner.isHidden = false
            Log.debug("Playback stalled")
        }
    }
    
    private func observeLoadedTimeRanges(_ item: AVPlayerItem) -> NSKeyValueObservation {
        return item.observe(\.loadedTimeRanges) { [weak self] item, _ in
            let loadedTimeRanges = item.loadedTimeRanges
            if loadedTimeRanges.count > 1 {
                print("More than one loaded time range: \(loadedTimeRanges)")
            }
            
            guard let loadedTimeRange = loadedTimeRanges.first?.timeRangeValue else {
                Log.error("Empty loaded time ranges")
                return
            }
            
            let bufferProgress = Float(loadedTimeRange.end.seconds / item.duration.seconds)
            self?.playbackBufferProgressView.setProgress(bufferProgress, animated: true)
        }
    }
}

// MARK: - Audio Session

extension CustomPlayerViewController {
    private func setUpPlaybackSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // TODO: Should setCategory be in AppDelegate?
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true, options: [])
        } catch { Log.error("Failed to setup audio session - %@", error) }
    }
    
    // TODO: Decide where to call this, especially with PiP
    private func tearDownPlaybackSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(false, options: [])
        } catch { Log.error("Failed to teardown audio session - %@", error) }
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
        play(m3u8TestPlayerItem)
        
        super.viewWillAppear(animated)
    }
}
