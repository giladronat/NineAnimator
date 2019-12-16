//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2019 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import AVFoundation
import Foundation

/// This file contains the polyfills to make NineAnimator run on Simulators with older system versions
///
/// Older systems will throw an Objective C exception (symbol not found) for AVAsset download task.
/// This file provides the dummy classes for those missing symbols. And, of course, AVAsset
/// downloads won't work on simulators.

#if targetEnvironment(simulator)
/// A dummmy class for AVAssetDownloadTask
class AVAssetDownloadTask: URLSessionTask {
    var urlAsset: AVURLAsset {
        return AVURLAsset(url: URL(fileURLWithPath: "/tmp/doesnotexists"))
    }
    
    override init() {
        super.init()
    }
}

/// A dummy class for AVAssetDownloadURLSession
class AVAssetDownloadURLSession: URLSession {
    func makeAssetDownloadTask(
          asset URLAsset: AVURLAsset,
          assetTitle title: String,
          assetArtworkData artworkData: Data?,
          options: [String: Any]? = nil) -> AVAssetDownloadTask? {
        Log.error("[AVAssetDownloadURLSession] AVAssetDownloadURLSession is not available on the simulator")
        return nil
    }
    
    override init() {
        super.init()
    }
    
    convenience init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate?, delegateQueue queue: OperationQueue?) {
        self.init()
    }
    
    convenience init(configuration: URLSessionConfiguration,
                     assetDownloadDelegate delegate: AVAssetDownloadDelegate?,
                     delegateQueue: OperationQueue?) {
        self.init()
    }
    
    override func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) {
        DispatchQueue.main.async {
            completionHandler([])
        }
    }
}
#endif
