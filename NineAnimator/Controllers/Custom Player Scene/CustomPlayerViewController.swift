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
    @IBOutlet private weak var controlContainerOverlay: UIView!
    
    private var isDisplayingControls = true
    private var fadeControlsTimer: Timer?
    private var fadeControlsTimeInterval: TimeInterval = 3.0
    @IBOutlet private weak var viewTappedGestureRecognizer: UITapGestureRecognizer!
    
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet private weak var currentPlaybackTimeLabel: UILabel! {
        didSet {
            currentPlaybackTimeLabel.font = currentPlaybackTimeLabel.font.monospacedDigitFont
        }
    }
    @IBOutlet private weak var timeToEndLabel: UILabel! {
        didSet {
            timeToEndLabel.font = timeToEndLabel.font.monospacedDigitFont
        }
    }
    @IBOutlet private weak var totalTimeLabel: UILabel! {
        didSet {
            totalTimeLabel.font = totalTimeLabel.font.monospacedDigitFont
        }
    }
    
    @IBOutlet private weak var bufferSpinner: UIActivityIndicatorView!
    
    @IBOutlet private weak var playbackProgressSlider: UISlider!
    @IBOutlet private weak var playbackBufferProgressView: UIProgressView!
    @IBOutlet private weak var rewindButton: UIButton!
    @IBOutlet private weak var rewindContainer: UIView!
    @IBOutlet private weak var rewindDoubleTapGestureRecognizer: UITapGestureRecognizer!
    @IBOutlet private weak var fastForwardButton: UIButton!
    @IBOutlet private weak var fastForwardContainer: UIView!
    @IBOutlet private weak var fastForwardDoubleTapGestureRecognizer: UITapGestureRecognizer!
    
    private var skipDurationTimeInterval: TimeInterval = 15.0
    
    private var isPlaybackProgressSliding = false
    private var wasPlayingBeforeSliding = false
    
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
        playButton.setImage(#imageLiteral(resourceName: "Pause Icon"), for: .normal)
    }
    
    private func pause() {
        player.pause()
        
        // Reflect UI
        playButton.setImage(#imageLiteral(resourceName: "Play Icon"), for: .normal)
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
    
    private func updatePlaybackUI(with currentTime: CMTime) {
        guard let item = self.playerItem else {
            Log.debug("No player item to update playback UI")
            // This probably won't happen
            currentPlaybackTimeLabel.text = "00:00"
            timeToEndLabel.text = "-00:00"
            totalTimeLabel.text = "00:00"
            return
        }
        
        let currentPlaybackSeconds = currentTime.seconds
        let timeToEndSeconds = item.duration.seconds - currentTime.seconds
        let currentPlaybackString = self.format(timeInterval: currentPlaybackSeconds)
        let timeToEndString = "-\(self.format(timeInterval: timeToEndSeconds))"
        
        currentPlaybackTimeLabel.text = currentPlaybackString
        timeToEndLabel.text = timeToEndString
        // totalTimeLabel ~> item.duration is updated when item becomes ready to play and doesn't change afterward
        
        if !isPlaybackProgressSliding {
            self.playbackProgressSlider.setValue(Float(currentPlaybackSeconds), animated: true)
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
            // Update UI
            if !(self?.isPlaybackProgressSliding ?? true) {
                // If sliding, slider handles UI update
                self?.updatePlaybackUI(with: time)
            }
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
                
                // Allow controls to stay visible when paused
                self?.fadeControlsTimer?.invalidate()
            case .playing:
                Log.debug("Status: playing")
                self?.setFadeControlsTimer()
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
                Log.debug("Empty loaded time ranges")
                // TODO: Maybe clear buffer progress
                return
            }
            
            let bufferProgress = Float(loadedTimeRange.end.seconds / item.duration.seconds)
            self?.playbackBufferProgressView.setProgress(bufferProgress, animated: true)
        }
    }
}

// MARK: - Seeking

extension CustomPlayerViewController {
    func seek(by offsetSeconds: TimeInterval) {
        let currentTime = player.currentTime()
        let seekTime = CMTime(seconds: currentTime.seconds + offsetSeconds)
//        Log.debug("Seeking: %@", format(timeInterval: seekTime.seconds))
        
        // AVPlayer automatically clamps seeking to item.seekableTimeRanges
        // Therefore, no need to guard against seeking before 0 or after end time
        
        // Impressively, it also handles the buffering on its own -- we get callbacks
        player.seek(to: seekTime)
    }
    
    func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: time))
    }
    
    @IBAction private func fastForwardTapped(_ sender: Any) {
        seek(by: skipDurationTimeInterval)
    }
    
    @IBAction private func rewindTapped(_ sender: Any) {
        seek(by: -skipDurationTimeInterval)
    }
    
    @IBAction private func forwardDoubleTapped(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            seek(by: skipDurationTimeInterval)
        }
    }
    @IBAction private func rewindDoubleTapped(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            seek(by: -skipDurationTimeInterval)
        }
    }
    
    @IBAction private func playbackProgressSliderValueChanged(_ sender: UISlider) {
        // Update time label while sliding instead of relying on playback time change
        // Lets user "preview" the time they slide to before seeking completes
        isPlaybackProgressSliding = true
        let sliderSecondsValue = sender.value
        updatePlaybackUI(with: CMTime(seconds: Double(sliderSecondsValue)))
        seek(to: TimeInterval(sliderSecondsValue))
    }
    
    @IBAction private func playbackProgressSliderTouchDown(_ sender: UISlider) {
        isPlaybackProgressSliding = true
        wasPlayingBeforeSliding = player.timeControlStatus == .playing
        viewTappedGestureRecognizer.isEnabled = false // disables viewTapped hiding controls when not dragging
        fadeControlsTimer?.invalidate()
        player.pause()
    }
    
    @IBAction private func playbackProgressSliderTouchUp(_ sender: UISlider) {
        isPlaybackProgressSliding = false
        viewTappedGestureRecognizer.isEnabled = true
        if wasPlayingBeforeSliding {
            setFadeControlsTimer()
            player.play()
        }
    }
}

// MARK: - Control Fading

extension CustomPlayerViewController {
    private func setFadeControlsTimer() {
        fadeControlsTimer?.invalidate()
        fadeControlsTimer = Timer.scheduledTimer(withTimeInterval: fadeControlsTimeInterval,
                                                 repeats: false) { [weak self] _ in
                                                    self?.displayControls(false)
        }
    }
    
    @IBAction private func viewTapped(_ sender: UITapGestureRecognizer) {
        displayControls(!isDisplayingControls)
    }
    
    /// Makes viewTapped wait to make sure there's no double tap.
    // Otherwise, viewTapped gets called immediately
    private func prepareGestureRecognizers() {
        viewTappedGestureRecognizer.require(toFail: rewindDoubleTapGestureRecognizer)
        viewTappedGestureRecognizer.require(toFail: fastForwardDoubleTapGestureRecognizer)
        // Gesture also disabled when tapping inside progress slider
    }
    
    private func displayControls(_ visible: Bool) {
        if visible {
            showControls()
        } else {
            hideControls()
        }
    }
    
    private func showControls() {
        // TODO: Animate
        controlContainerOverlay.isHidden = false
        if player.timeControlStatus == .playing {
            // Do not fade controls when paused
            setFadeControlsTimer()
        }
        isDisplayingControls = true
    }
    
    private func hideControls() {
        controlContainerOverlay.isHidden = true
        fadeControlsTimer?.invalidate()
        isDisplayingControls = false
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

// MARK: - Life Cycle

extension CustomPlayerViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        prepareGestureRecognizers()
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

// MARK: - Tasks

/*
 
 Features:

 - [ ] Hide controls after certain time
    - [ ] Hold finger on screen to keep controls on
 - [ ] Next episode button
 - [ ] iPad PiP
 - [ ] User activity & continuity (via NativePlayerController)
 - [ ] Progress saving & restoration (done in NativePlayerController)
 - [ ] Button to change aspect zooming (like native double-tap)
 - [ ] Auto-play option
 - [X] Double-tap skip gesture
 
 Clean-up:
 
 - [ ] Clean up UI modification with respect to the player item
 (possibly extract to a view model)
 - [ ] Document potential statuses better
 - [ ] Decide on which public APIs to expose to make code reusable
 - [ ] See which parts of the code can and should be tested
 
 Details:
 
 - [X] Check gesture recognizers' .delaysTouchesBegan/Ended
 - [ ] Disable & enable controls based on item ready/buffering
 - [ ] Swapping between spinner and play/pause when buffering
 - [ ] Determine good placeholder values that don't mess with layout
 - [ ] Stack double-tap skips like Netflix/Twitch
 
*/
