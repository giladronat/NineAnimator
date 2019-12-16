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

extension NineAnimatorUser {
    /// Default keys of NineAnimator
    enum Keys {
        static var version: String { return "com.marcuszhou.nineanimator.version" }
        static var recentAnimeList: String { return "anime.recent" }
        static var detectClipboardAnimeLinks: String { return "anime.links.detect" }
        static var subscribedAnimeList: String { return "anime.subscribed" }
        static var allowNSFWContent: String { return "anime.content.nsfw" }
        static var autoRestartInterruptedDownloadTasks: String { return "episode.download.autorestart" }
        static var preventAVAssetPurge: String { return "episode.download.preventPurge" }
        static var sendDownloadNotifications: String { return "episode.download.sendDownloadNotifications" }
        static var recentEpisode: String { return "episode.recent" }
        static var recentSource: String { return "source.recent" }
        static var sourceSolveChallenges: String { return "source.challengeSolver" }
        static var recentServer: String { return "server.recent" }
        static var persistedProgresses: String { return "episode.progress" }
        static var episodeListingOrder: String { return "episode.listing.order" }
        static var episodeDetails: String { return "episode.details" }
        static var backgroundPlayback: String { return "playback.background" }
        static var pictureInPicturePlayback: String { return "playback.pip" }
        static var notificationShowStream: String { return "notification.showStreams" }
        static var homeExternalOnly: String { return "home.externalOnly" }
        static var homeUUIDStart: String { return "home.actionset.uuid.start" }
        static var homeUUIDEnd: String { return "home.actionset.uuid.end" }
        static var theme: String { return "interface.theme" }
        static var brightnessBasedTheme: String { return "interface.brightnessBasedTheme" }
        
        // Watching anime episodes persist filename
        static var watchedAnimesFileName: String { return "com.marcuszhou.NineAnimator.anime.watching.plist" }
    }
    
    /// A property wrapper for an entry in the UserDefaults
    @propertyWrapper
    struct Entry<ValueType> {
        private let key: String
        private unowned var store: UserDefaults
        private let defaultValue: ValueType
        
        var wrappedValue: ValueType {
            get {
                if let value = store.value(forKey: key) as? ValueType {
                    return value
                } else { return defaultValue }
            }
            set { store.set(newValue, forKey: key) }
        }
        
        init(_ key: String, store: UserDefaults, default: ValueType) {
            self.key = key
            self.store = store
            self.defaultValue = `default`
        }
    }
}
