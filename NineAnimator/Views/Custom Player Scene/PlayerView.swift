//
//  PlayerView.swift
//  NineAnimator
//
//  Created by Gilad Ronat on 7/31/19.
//  Copyright © 2019 Marcus Zhou. All rights reserved.
//

import AVFoundation
import UIKit

// Basic AVPlayerLayer view
// https://developer.apple.com/documentation/avfoundation/avplayerlayer

class PlayerView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        
        set {
            playerLayer.player = newValue
        }
    }
}

