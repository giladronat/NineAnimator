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

import Kingfisher
import UIKit
import UserNotifications

/**
 A structure used to persist episode information.
 */
struct WatchedAnime: Codable {
    let link: AnimeLink
    let episodeNames: [String]
    let lastCheck: Date
}

/// A standalone class used to manage fetch requests and updates
///
/// This class manages the persisted anime watchers, perform fetches for updates, and sends notifications
/// to the user related to events happening in NineAnimator.
class UserNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    // Exposed properties
    static let `default` = UserNotificationManager()
    
    let suggestedFetchInterval: TimeInterval = 3600
    
    // Private properties
    
    private var taskPool: [NineAnimatorAsyncTask?]? // Hold references to async tasks
    
    private var lazyPersistPool = Set<AnimeLink>()
    
    private var persistentTaskIdentifier: UIBackgroundTaskIdentifier?
    
    private let animeCachingDirectory: URL
    
    private let subscriptionRecommendationSource = SubscribedAnimeRecommendationSource()
    
    override init() {
        let fileManager = FileManager.default
        self.animeCachingDirectory = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        super.init()
        
        // Cache lazy persist data when the app resigns active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppBecomesInactive(notification:)),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // Add observer for downloading task update
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDownloadingTaskUpdate(_:)),
            name: .offlineAccessStateDidUpdate,
            object: nil
        )
        
        // Tell the system what categories of notifications this app supports
        registerNotificationCategories()
        
        // Add anime subscription as a recommendation source
        NineAnimator.default.register(additionalRecommendationSource: subscriptionRecommendationSource)
    }
}

// MARK: - Initialization
extension UserNotificationManager {
    enum NotificationCategory {
        /// Notifications for updated anime
        static let animeUpdate = "com.marcuszhou.NineAnimator.notificaiton.category.animeUpdates"
        
        /// Notifications for downloads
        static let downloads = "com.marcuszhou.NineAnimator.notificaiton.category.downloads"
    }
    
    enum NotificationAction {
        /// Open NineAnimator and view the notification
        static let open = "com.marcuszhou.NineAnimator.notificaiton.action.open"
    }
    
    private func registerNotificationCategories() {
        // Available Actions
        let openAction = UNNotificationAction(
            identifier: NotificationAction.open,
            title: "View",
            options: [ .foreground ]
        )
        
        // Available Categories
        let animeUpdateCategory = UNNotificationCategory(
            identifier: NotificationCategory.animeUpdate,
            actions: [ openAction ],
            intentIdentifiers: [],
            options: []
        )
        
        let downloadsCategory = UNNotificationCategory(
            identifier: NotificationCategory.downloads,
            actions: [ openAction ],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            animeUpdateCategory, downloadsCategory
        ])
    }
    
    /// Request User's permission for pushing notifications
    func requestNotificationPermissions() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.requestAuthorization(options: [.badge]) {
            success, _ in DispatchQueue.main.async {
                if !success {
                    let alertController = UIAlertController(title: "Updates Unavailable", message: "NineAnimator doesn't have persmission to send notifications. You won't receive any updates for this anime until you allow notifications from NineAnimator in Settings.", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    RootViewController.shared?.presentOnTop(alertController, animated: true)
                }
            }
        }
    }
}

// MARK: - App state handling
extension UserNotificationManager {
    @objc func onAppBecomesInactive(notification: Notification) {
        // Don't do anything if another background task is running
        guard taskPool == nil else { return }
        
        if !lazyPersistPool.isEmpty {
            Log.info("Caching subscribed anime.")
            
            let concludeLazyPersist = {
                [weak self] () -> Void in
                Log.info("Finish caching subscribed anime.")
                guard let identifier = self?.persistentTaskIdentifier else { return }
                UIApplication.shared.endBackgroundTask(identifier)
                self?.persistentTaskIdentifier = nil
                self?.taskPool = nil
            }
            
            persistentTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: concludeLazyPersist)
            
            var counter = 0
            
            taskPool = lazyPersistPool.compactMap {
                // Retrieve each lazy persist anime
                $0.retrive { [weak self] anime, error in
                    defer {
                        counter -= 1
                        if counter == 0, let identifier = self?.persistentTaskIdentifier {
                            concludeLazyPersist()
                        }
                    }
                
                    guard let anime = anime else {
                        Log.error("Unable to persist data - %@", error!)
                        return
                    }
                    
                    self?.update(anime)
                }
            }
            counter = taskPool!.count
            lazyPersistPool.removeAll()
        }
    }
}

// MARK: - File path helpers
extension UserNotificationManager {
    /// Returns the location where the anime watcher is being persisted
    private func url(for anime: AnimeLink) -> URL {
        return self.animeCachingDirectory.appendingPathComponent(.animePersistFilenameComponent(anime))
    }
    
    /// Returns the location where the copied poster image is located at
    private func posterUrl(for anime: AnimeLink) -> URL {
        return self.animeCachingDirectory.appendingPathComponent(.cachedPosterFilenameComponent(anime))
    }
}

// MARK: - Watcher Persistent
extension UserNotificationManager {
    /// Retrive the watcher for the anime from the file system
    func retrive(for anime: AnimeLink) -> WatchedAnime? {
        do {
            let persistUrl = self.url(for: anime)
            if FileManager.default.fileExists(atPath: persistUrl.path),
                try persistUrl.checkResourceIsReachable() {
                let serializedWatcher = try Data(contentsOf: persistUrl)
                let decoer = PropertyListDecoder()
                return try decoer.decode(WatchedAnime.self, from: serializedWatcher)
            }
        } catch { Log.error("Unable to retrive watcher for anime - %@", error) }
        return nil
    }
    
    /// Persist the watcher for the anime to the file system
    func persist(_ watcher: WatchedAnime) {
        do {
            let persistUrl = self.url(for: watcher.link)
            let encoder = PropertyListEncoder()
            let serializedWatcher = try encoder.encode(watcher)
            try serializedWatcher.write(to: persistUrl)
            lazyPersistPool.remove(watcher.link)
        } catch { Log.error("Unable to persist watcher - %@", error) }
    }
    
    /// Add the anime but do not cache the episodes until the app becomes inactive or the user enters the anime.
    ///
    /// - Note: See persist(_ watcher: WatchedAnime)
    func lazyPersist(_ link: AnimeLink, shouldFireSubscriptionEvent: Bool = false) {
        lazyPersistPool.insert(link)
        
        if shouldFireSubscriptionEvent {
            subscriptionRecommendationSource.fireDidUpdateNotification()
        }
    }
    
    /// Update cached anime episodes
    func update(_ anime: Anime, shouldFireSubscriptionEvent: Bool = false) {
        let newWatcher = WatchedAnime(
            link: anime.link,
            episodeNames: anime.episodes.uniqueEpisodeNames,
            lastCheck: Date()
        )
        persist(newWatcher)
        
        if shouldFireSubscriptionEvent {
            subscriptionRecommendationSource.fireDidUpdateNotification()
        }
    }
    
    /// Update cached anime episodes
    func remove(_ anime: AnimeLink) {
        // Fire update event
        subscriptionRecommendationSource.fireDidUpdateNotification()
        
        // Check if the anime is not yet fetched
        guard lazyPersistPool.remove(anime) == nil else { return }
        
        do {
            let fileManager = FileManager.default
            try fileManager.removeItem(at: url(for: anime))
            
            // Not deleting the poster since it should be remvoed by the
            // user notification center
            
            // try fileManager.removeItem(at: posterUrl(for: anime))
        } catch { Log.error("Unable to remove persisted watcher - %@", error) }
    }
    
    /// Clear all cached anime
    func removeAll() {
        do {
            let fileManager = FileManager.default
            let enumeratedItems = try fileManager.contentsOfDirectory(
                at: animeCachingDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )
            try enumeratedItems.forEach(fileManager.removeItem)
        } catch { Log.error("Unable to remove persisted watcher - %@", error) }
    }
    
    /// Remove posted notifications about this anime
    func clearNotifications(for anime: AnimeLink) {
        let notificationCenter = UNUserNotificationCenter.current()
        let viewedAnimeNotificationIdentifiers: [String] = [.episodeUpdateNotificationIdentifier(anime)]
        notificationCenter.removeDeliveredNotifications(withIdentifiers: viewedAnimeNotificationIdentifiers)
    }
    
    /// Check whether a notification was sent to the user for the specified anime link
    func hasNotifications(for anime: AnimeLink, _ handler: @escaping NineAnimatorCallback<Bool>) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getDeliveredNotifications {
            notifications in
            handler(
                notifications.contains { $0.request.identifier == .episodeUpdateNotificationIdentifier(anime) },
                nil
            )
        }
    }
    
    /// An alias of `hasNotifications(for anime:, _ handler:)` that returns a promise
    func hasNotifications(for anime: AnimeLink) -> NineAnimatorPromise<Bool> {
        return NineAnimatorPromise {
            self.hasNotifications(for: anime, $0)
            return nil
        }
    }
    
    /// Retrieve the list of anime with notifications delivered to
    func animeWithNotifications(searchIn pool: [AnimeLink] = NineAnimator.default.user.subscribedAnimes) -> NineAnimatorPromise<[AnimeLink]> {
        return NineAnimatorPromise<[UNNotification]> {
            callback in
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getDeliveredNotifications { callback($0, nil) }
            return nil
        } .then {
            notifications in pool.filter {
                link in notifications.contains {
                    $0.request.identifier == .episodeUpdateNotificationIdentifier(link)
                }
            }
        }
    }
}

// MARK: - Episode fetching
extension UserNotificationManager {
    fileprivate typealias FetchResult = (anime: AnimeLink, newEpisodeTitles: [String], availableServerNames: [String])
    
    /// Perform the fetch operation
    func performFetch(with completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Do not perform fetch if the last one is incomeplete
        guard taskPool == nil else {
            Log.info("Cancelling background fetch since another task is in progress.")
            return completionHandler(.failed)
        }
        
        let synchronizingQueue = DispatchQueue.global()
        let watchedAnimeLinks = NineAnimator.default.user.subscribedAnimes
        var resultsPool = [FetchResult?]()
        
        guard !watchedAnimeLinks.isEmpty else {
            return completionHandler(.noData)
        }
        
        let onFinalTask = { [weak self] () -> Void in
            let succeededResultsCount = resultsPool
                .compactMap { $0 }
                .count
            let newResultsCount = resultsPool
                .filter { ($0?.newEpisodeTitles.count ?? 0) > 0 }
                .count
            let finalFetchResult: UIBackgroundFetchResult =
                succeededResultsCount == watchedAnimeLinks.count ?
                ( newResultsCount > 0 ? .newData : .noData )
                : .failed
            Log.info("Background fetch finished with result: %@", finalFetchResult.rawValue)
            self?.taskPool = nil
            completionHandler(finalFetchResult)
        }
        
        Log.info("Beginning background fetch with %@ watched anime.", watchedAnimeLinks.count)
        
        taskPool = watchedAnimeLinks.map { animeLink in
            // Ignore the watcher that is fetched within 2 hours
            if let watcher = self.retrive(for: animeLink), watcher.lastCheck.timeIntervalSinceNow >= -7200 {
                Log.info("Skipping '%@' (last checked: %@, %@ seconds since now", animeLink.title, watcher.lastCheck, watcher.lastCheck.timeIntervalSinceNow)
                resultsPool.append(FetchResult(animeLink, [], []))
                return nil
            }
            
            return animeLink.retrive { [weak self] anime, _ in
                synchronizingQueue.async {
                    guard let self = self else { return }
                    
                    defer { if resultsPool.count == watchedAnimeLinks.count { onFinalTask() } }
                    
                    guard let anime = anime else { return resultsPool.append(nil) }
                    
                    var result = FetchResult(animeLink, [], [])
                    
                    if let currentWatcher = self.retrive(for: animeLink) {
                        result.newEpisodeTitles = anime.episodes.uniqueEpisodeNames.filter {
                            !currentWatcher.episodeNames.contains($0)
                        }
                        result.availableServerNames = result
                            .newEpisodeTitles
                            .flatMap(anime.episodes.links)
                            .reduce(into: [Anime.ServerIdentifier]()) {
                                if !$0.contains($1.server) {
                                    $0.append($1.server)
                                }
                            }
                            .compactMap { anime.servers[$0] }
                        
                        // Post notification to user
                        self.sendAnimeUpdateNotification(result: result)
                    } else { Log.info("Anime '%@' is being registered but has not been cached yet. No new notifications will be sent.", anime.link.title) }
                    
                    // If unable to retrive the persisted episodes (maybe deleted by the system)
                    // Just store the latest version without posting any notifications.
                    self.update(anime)
                    
                    // Add the results to the pool
                    resultsPool.append(result)
                    
                    // This is just in case we skipped everything
                    if resultsPool.count == watchedAnimeLinks.count { onFinalTask() }
                }
            }
        }
    }
}

// MARK: - Presenting Notifications
extension UserNotificationManager {
    /// Post anime update notification to user
    private func sendAnimeUpdateNotification(result: FetchResult) {
        guard !result.newEpisodeTitles.isEmpty else { return }
        
        let notificationCenter = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        
        content.title = "\(result.anime.title)"
        content.categoryIdentifier = NotificationCategory.animeUpdate
    
        let streamingSites = result.availableServerNames.joined(separator: ", ")
        let sourceName = result.anime.source.name
        
        if result.newEpisodeTitles.count == 1 {
            content.body = "Episode \(result.newEpisodeTitles.first!) is now available on \(sourceName)."
        } else {
            content.body = "\(result.newEpisodeTitles.count) more episodes are now available on \(sourceName)."
        }
        
        // Sometimes showing what stream the anime is on can be helpful
        if NineAnimator.default.user.notificationShowStreams {
            content.body += " Stream now from \(streamingSites)."
        }
        
        do {
            let encoder = PropertyListEncoder()
            let linkData = try encoder.encode(result.anime)
            content.userInfo = [ "link": linkData ]
        } catch {
            Log.error("Unable to encode AnimeLink to notificaiton (%@). Aborting notificaiton.", error)
            return
        }
        
        // Generate to poster attachement
        if let posterAttachment = self.generateNotificationAttachment(for: result.anime) {
            content.attachments.append(posterAttachment)
        }
        
        let request = UNNotificationRequest(
            identifier: .episodeUpdateNotificationIdentifier(result.anime),
            content: content,
            trigger: nil
        )
        
        // Alas, post notification to the user
        notificationCenter.add(request, withCompletionHandler: nil)
        
        Log.info("Notification for '%@' sent.", result.anime.title)
    }
    
    /// Send a download status update notification
    func sendDownloadsNotification(_ content: OfflineContent) {
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationContent = UNMutableNotificationContent()
        notificationContent.categoryIdentifier = NotificationCategory.downloads
        
        switch content.state {
        case .error:
            notificationContent.title = "Download Failed"
            notificationContent.body = "Downloading task for \(content.localizedDescription) has failed."
            
            if NineAnimator.default.user.autoRestartInterruptedDownloads {
                notificationContent.body += " NineAnimator will retry when possible."
            }
        case .preserved:
            notificationContent.title = "Episode Now Available Offline"
            notificationContent.body = "\(content.localizedDescription) is now available for offline viewing."
        default: return
        }
        
        // If the OfflineContent is an instance of OfflineEpisodeContent,
        // generate the attachment from the artwork of its parent AnimeLink
        if let episodeContent = content as? OfflineEpisodeContent,
            let generatedAttachment = generateNotificationAttachment(for: episodeContent.episodeLink.parent) {
            notificationContent.attachments.append(generatedAttachment)
        }
        
        let request = UNNotificationRequest(
            identifier: .downloadUpdateNotificationIdentifier(content),
            content: notificationContent,
            trigger: nil
        )
        
        // Enqueue the notification
        notificationCenter.add(request, withCompletionHandler: nil)
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Present the notificaiton as badge
        completionHandler(.badge)
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        // Obtain the content of the notification
        let content = response.notification.request.content
        let decoder = PropertyListDecoder()
        
        switch content.categoryIdentifier {
        case NotificationCategory.animeUpdate:
            guard let serializedAnimeLink = content.userInfo["link"] as? Data,
                let animeLink = try? decoder.decode(AnimeLink.self, from: serializedAnimeLink) else {
                    Log.error("[UserNotificationManager] Unable to deserialize AnimeLink. Won't present notification.")
                    return
            }
            
            Log.info("[UserNotificationManager] Presenting notification with link %@", animeLink)
            RootViewController.open(whenReady: .anime(animeLink))
            completionHandler()
        case NotificationCategory.downloads:
            // Navigate to library for downloads
            RootViewController.navigateWhenReady(toScene: .library)
            completionHandler()
        default:
            Log.error("[UserNotificationManager] Unknown notification category: %@", content.categoryIdentifier)
            completionHandler()
        }
    }
    
    @objc private func onDownloadingTaskUpdate(_ notification: Notification) {
        guard NineAnimator.default.user.sendDownloadsNotifications,
            AppDelegate.shared?.isActive != true,
            let content = notification.object as? OfflineContent else { return }
        
        // Notify the user when the downloads have finished/errored
        switch content.state {
        case .error, .preserved: sendDownloadsNotification(content)
        default: return
        }
    }
    
    /// Copy the cached artwork for the anime to a temporary location and generate a
    /// `UNNotificationAttachment` for that artwork
    private func generateNotificationAttachment(for animeLink: AnimeLink) -> UNNotificationAttachment? {
        do {
            let posterUrl = self.posterUrl(for: animeLink)
            
            // Copy from Kingfisher image cache
            let cache = Kingfisher.ImageCache.default
            let cacheKey = animeLink.image.absoluteString
            let cachedPosterPath = cache.cachePath(forKey: cacheKey)
            
            // Only show poster if the poster is cached, or an error is expected to be thrown
            let poster = UIImage(contentsOfFile: cachedPosterPath)
            try poster?.jpegData(compressionQuality: 0.8)?.write(to: posterUrl)
            
            return try UNNotificationAttachment(
                identifier: "", // Let the framework create the identifier
                url: posterUrl,
                options: nil
            )
        } catch {
            Log.error("[UserNotificationManager] Unable to create notifiction attachment: %@", error)
            return nil
        }
    }
}

// MARK: - Notification identifiers/File Name paths
extension String {
    static func episodeUpdateNotificationIdentifier(_ anime: AnimeLink) -> String {
        let linkHashRepresentation = anime.link.uniqueHashingIdentifier
        return "com.marcuszhou.NineAnimator.notification.episodeUpdates.\(linkHashRepresentation)"
    }
    
    static func downloadUpdateNotificationIdentifier(_ content: OfflineContent) -> String {
        return "com.marcuszhou.NineAnimator.notification.episodeUpdates.\(content.identifier.uniqueHashingIdentifier)"
    }
    
    static func animePersistFilenameComponent(_ anime: AnimeLink) -> String {
        let linkHashRepresentation = anime.link.uniqueHashingIdentifier
        return "com.marcuszhou.NineAnimator.anime.\(linkHashRepresentation).plist"
    }
    
    static func cachedPosterFilenameComponent(_ anime: AnimeLink) -> String {
        let linkHashRepresentation = anime.link.uniqueHashingIdentifier
        return "com.marcuszhou.NineAnimator.poster.\(linkHashRepresentation).jpg"
    }
}
