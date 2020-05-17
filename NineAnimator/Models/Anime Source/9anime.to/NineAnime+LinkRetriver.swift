//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2020 Marcus Zhou. All rights reserved.
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
import SwiftSoup

extension NASourceNineAnime {
    static let animeLinkParsingRegex = try! NSRegularExpression(pattern: "\\/watch\\/([^/]+)", options: .caseInsensitive)
//    static let episodeLinkParsingRegex = try! NSRegularExpression(pattern: "\\/watch\\/[^/]+\\/([0-9A-Za-z]+)", options: .caseInsensitive)
    
    func link(from url: URL, _ handler: @escaping NineAnimatorCallback<AnyLink>) -> NineAnimatorAsyncTask? {
        let urlString = url.absoluteString
        
        guard let animeIdentifierMatch = NASourceNineAnime.animeLinkParsingRegex.matches(
            in: urlString,
            options: [],
            range: urlString.matchingRange
            ).first else {
            handler(nil, NineAnimatorError.urlError)
            return nil
        }
        
        let animeIdentifier = urlString[animeIdentifierMatch.range(at: 1)]
//        var episodeIdentifier: String?
//
//        if let episodeIdentifierMatch = NASourceNineAnime.episodeLinkParsingRegex.matches(
//            in: urlString,
//            options: [],
//            range: urlString.matchingRange
//            ).first {
//            episodeIdentifier = urlString[episodeIdentifierMatch.range(at: 1)]
//        }
        
        let reconstructedAnimePath = "/watch/\(animeIdentifier)"
        guard let reconstructedAnimeLink = URL(string: "\(endpoint)\(reconstructedAnimePath)") else {
            handler(nil, NineAnimatorError.urlError)
            return nil
        }
        
        let task = AsyncTaskContainer()
        
        task.add(request(browse: url, headers: [:]) {
            [weak self] content, requestError in
            guard let self = self else { return }
            guard let content = content else { return handler(nil, requestError) }
            
            do {
                let bowl = try SwiftSoup.parse(content)
                let animeInfoContainer = try bowl.select(".widget.info")
                
                let posterUrl = URL(string: try animeInfoContainer.select(".thumb>img").attr("src"))!
                let animeTitle = try animeInfoContainer.select("h2.title").text()
                
                let animeLink = AnimeLink(
                    title: animeTitle,
                    link: reconstructedAnimeLink,
                    image: posterUrl,
                    source: self
                )
                
                handler(.anime(animeLink), nil)
            } catch { handler(nil, error) }
        })
        
        return task
    }
}
