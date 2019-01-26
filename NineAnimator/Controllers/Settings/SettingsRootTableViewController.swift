//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018 Marcus Zhou. All rights reserved.
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

import AVKit
import Kingfisher
import SafariServices
import UIKit
import UserNotifications

// swiftlint:disable cyclomatic_complexity
class SettingsRootTableViewController: UITableViewController {
    @IBOutlet private weak var episodeListingOrderControl: UISegmentedControl!
    
    @IBOutlet private weak var detectClipboardLinksSwitch: UISwitch!
    
    @IBOutlet private weak var viewingHistoryStatsLabel: UILabel!
    
    @IBOutlet private weak var backgroundPlaybackSwitch: UISwitch!
    
    @IBOutlet private weak var pictureInPictureSwitch: UISwitch!
    
    @IBOutlet private weak var subscriptionStatsLabel: UILabel!
    
    @IBOutlet private weak var subscriptionStatusLabel: UILabel!
    
    @IBOutlet private weak var subscriptionShowStreamsSwitch: UISwitch!
    
    @IBOutlet private weak var appearanceSegmentControl: UISegmentedControl!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreferencesUI()
    }
    
    @IBAction private func onDetectClipboardLinksChange(_ sender: UISwitch) {
        NineAnimator.default.user.detectsPasteboardLinks = sender.isOn
    }
    
    @IBAction private func onEpisodeListingOrderChange(_ sender: UISegmentedControl) {
        defer { NineAnimator.default.user.push() }
        
        switch sender.selectedSegmentIndex {
        case 0: NineAnimator.default.user.episodeListingOrder = .reversed
        case 1: NineAnimator.default.user.episodeListingOrder = .ordered
        default: return
        }
    }
    
    @IBAction private func onPiPDidChange(_ sender: UISwitch) {
        let newValue = sender.isOn
        NineAnimator.default.user.allowPictureInPicturePlayback = newValue
        updatePreferencesUI()
    }
    
    @IBAction private func onBackgroundPlaybackDidChange(_ sender: UISwitch) {
        NineAnimator.default.user.allowBackgroundPlayback = sender.isOn
    }
    
    @IBAction private func onShowStreamsInNotificationDidChange(_ sender: UISwitch) {
        NineAnimator.default.user.notificationShowStreams = sender.isOn
    }
    
    @IBAction private func onDoneButtonClicked(_ sender: Any) {
        dismiss(animated: true)
    }
    
    @IBAction private func onAppearanceDidChange(_ sender: UISegmentedControl) {
        let newAppearanceName = sender.selectedSegmentIndex == 0 ? "dark" : "light"
        guard let theme = Theme.availableThemes[newAppearanceName] else { return }
        Theme.setTheme(theme)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectSelectedRow() }
        
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        
        func askForConfirmation(title: String,
                                message: String,
                                continueActionName: String,
                                proceed: @escaping () -> Void) {
            let alertView = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
            
            if let popover = alertView.popoverPresentationController {
                popover.sourceView = cell.contentView
                popover.permittedArrowDirections = .any
            }
            
            let action = UIAlertAction(title: continueActionName, style: .destructive) { _ in proceed() }
            alertView.addAction(action)
            
            alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alertView, animated: true)
        }
        
        switch cell.reuseIdentifier {
        case "settings.viewrepo":
            let safariViewController = SFSafariViewController(url: URL(string: "https://github.com/SuperMarcus/NineAnimator")!)
            present(safariViewController, animated: true)
        case "settings.playback.cast.controller":
            RootViewController.shared?.showCastController()
        case "settings.history.recents":
            askForConfirmation(title: "Clear Recent Anime",
                               message: "This action is irreversible. All anime history under the Recents tab will be cleared.",
                               continueActionName: "Clear Recents"
            ) { [weak self] in
                NineAnimator.default.user.clearRecents()
                self?.updatePreferencesUI()
            }
        case "settings.history.cache":
            clearCache()
        case "settings.history.reset":
            askForConfirmation(title: "Reset NineAnimator",
                               message: "This action is irreversible. All data and preferences will be deleted from your local storage.",
                               continueActionName: "Reset"
            ) { [weak self] in
                NineAnimator.default.user.clearAll()
                self?.clearCache()
                self?.clearActivities()
                self?.updatePreferencesUI()
            }
        case "settings.notification.unsubscribe":
            askForConfirmation(title: "Unsubscribe from All",
                               message: "This action is irreversible. You will be unsubscribed from all anime.",
                               continueActionName: "Unsubscribe All"
            ) { [weak self] in
                NineAnimator.default.user.unwatchAll()
                self?.updatePreferencesUI()
            }
        case "settings.history.activities":
            askForConfirmation(title: "Delete All Activity Items",
                               message: "This action is irreversible. All existing Siri Shortcuts and Spotlight items will be deleted.",
                               continueActionName: "Clear Activities"
            ) { [weak self] in self?.clearActivities() }
        case "settings.history.export":
            guard let exportedSettingsUrl = export(NineAnimator.default.user) else {
                let alert = UIAlertController(title: "Error", message: "Cannot export configurations", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                return
            }
            
            let activityController = UIActivityViewController(activityItems: [exportedSettingsUrl], applicationActivities: nil)
            
            if let popoverController = activityController.popoverPresentationController {
                popoverController.sourceView = cell
            }
            
            present(activityController, animated: true, completion: nil)
        default: return
        }
    }
    
    private func clearCache() {
        Kingfisher.ImageCache.default.clearDiskCache()
        Kingfisher.ImageCache.default.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
        UserNotificationManager.default.removeAll()
    }
    
    private func clearActivities() {
        if #available(iOS 12.0, *) {
            NSUserActivity.deleteAllSavedUserActivities {
                [weak self] in self?.updatePreferencesUI()
            }
        }
    }
    
    private func updatePreferencesUI() {
        episodeListingOrderControl.selectedSegmentIndex = NineAnimator.default.user.episodeListingOrder == .reversed ? 0 : 1
        detectClipboardLinksSwitch.setOn(NineAnimator.default.user.detectsPasteboardLinks, animated: true)
        
        pictureInPictureSwitch.isEnabled = AVPictureInPictureController.isPictureInPictureSupported()
        pictureInPictureSwitch.setOn(AVPictureInPictureController.isPictureInPictureSupported() && NineAnimator.default.user.allowPictureInPicturePlayback, animated: true)
        
        backgroundPlaybackSwitch.isEnabled = !pictureInPictureSwitch.isOn
        backgroundPlaybackSwitch.setOn(NineAnimator.default.user.allowBackgroundPlayback || (AVPictureInPictureController.isPictureInPictureSupported() && NineAnimator.default.user.allowPictureInPicturePlayback), animated: true)
        
        appearanceSegmentControl.selectedSegmentIndex = NineAnimator.default.user.theme == "dark" ? 0 : 1
        
        //To be gramatically correct :D
        let recentAnimeCount = NineAnimator.default.user.recentAnimes.count
        viewingHistoryStatsLabel.text = "\(recentAnimeCount) \(recentAnimeCount > 1 ? "Items" : "Item")"
        
        let subscribedAnimeCount = NineAnimator.default.user.watchedAnimes.count
        subscriptionStatsLabel.text = "\(subscribedAnimeCount) \(subscribedAnimeCount > 1 ? "Items" : "Item")"
        
        subscriptionShowStreamsSwitch.setOn(NineAnimator.default.user.notificationShowStreams, animated: true)
        
        //Notification and fetch status
        var subscriptionEngineStatus = [String]()
        
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: break
        case .denied: subscriptionEngineStatus.append("App Refresh Denied")
        case .restricted: subscriptionEngineStatus.append("App Refresh Restricted")
        }
        
        UNUserNotificationCenter.current().getNotificationSettings {
            settings in
            if settings.authorizationStatus == .denied {
                subscriptionEngineStatus.append("Permission Denied")
            }
            
            DispatchQueue.main.async {
                [weak self] in
                self?.subscriptionStatusLabel.text = subscriptionEngineStatus.isEmpty ?
                    "Normal" : subscriptionEngineStatus.joined(separator: ", ")
            }
        }
    }
}
