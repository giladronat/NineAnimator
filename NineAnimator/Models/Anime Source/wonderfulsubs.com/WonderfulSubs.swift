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

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

class NASourceWonderfulSubs: BaseSource, Source, PromiseSource {
    var name: String { return "wonderfulsubs.com" }
    
#if canImport(UIKit)
    var siteLogo: UIImage { return #imageLiteral(resourceName: "WonderfulSubs Site Logo") }
#elseif canImport(AppKit)
    var siteLogo: NSImage { return #imageLiteral(resourceName: "WonderfulSubs Site Logo") }
#endif
    
    var aliases: [String] { return [
        "Wonderful Subs", "WonderfulSubs"
    ] }
    
    var siteDescription: String {
        return "WonderfulSubs is a free anime streaming website with numerous dubs and subs of anime. NineAnimator has fairly well-rounded support for this website."
    }
    
    override var endpoint: String { return "https://www.wonderfulsubs.com" }
    
    func suggestProvider(episode: Episode, forServer server: Anime.ServerIdentifier, withServerName name: String) -> VideoProviderParser? {
        if (episode.userInfo["custom.isPassthrough"] as? Bool) == true {
            return PassthroughParser.registeredInstance
        }
        
        if let host = episode.target.host {
            if let provider = VideoProviderRegistry.default.provider(for: host) {
                return provider
            } else {
                switch host {
                case _ where host.contains("fembed"):
                    return VideoProviderRegistry.default.provider(for: "fembed")
                default: Log.error("[NASourceWonderfulSubs] Unknown video provider %@", host)
                }
            }
        }
        
        return nil
    }
    
    override func recommendServer(for anime: Anime) -> Anime.ServerIdentifier? {
        return _recommendServer(for: anime)
    }
}
