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

import Alamofire
import Foundation

/// A passthrough parser that holds the reference to the PlaybackMedia
class PassthroughParser: VideoProviderParser {
    var aliases: [String] { return [] }
    
    func parse(episode: Episode, with session: SessionManager, forPurpose _: Purpose, onCompletion handler: @escaping NineAnimatorCallback<PlaybackMedia>) -> NineAnimatorAsyncTask {
        let dummyTask = AsyncTaskContainer()
        
        DispatchQueue.main.async {
            let options = episode.userInfo
            
            if let mediaRetriever = options[Options.playbackMediaRetriever] as? MediaRetriever {
                do {
                    handler(try mediaRetriever(episode).tryUnwrap(), nil)
                } catch { handler(nil, error) }
            } else { handler(nil, NineAnimatorError.providerError("No PlaybackMedia is specified for use with a PassthroughParser")) }
        }
        
        return dummyTask
    }
    
    typealias MediaRetriever = (Episode) throws -> PlaybackMedia?
    
    enum Options {
        static let playbackMediaRetriever: String =
        "com.marcuszhou.nineanimator.providerparser.PassthroughParser.mediaRetriever"
    }
    
    func isParserRecommended(forPurpose purpose: Purpose) -> Bool {
        return true
    }
}
