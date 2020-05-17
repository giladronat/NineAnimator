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
import HomeKit

/**
 Manages HomeKit integration
 
 Reference to `HomeController` is maintained in the `AppDelegate`.
 HomeController operates by tracking the updating playback
 progress notification.
 */
class HomeController: NSObject, HMHomeManagerDelegate {
    static let shared = HomeController()
    
    private var _isReady: Bool = false
    
    /// Cached instance of HMHomeManagerAuthorizationStatus
    /// - Note: Annotated as Any? for backwards-compatibility
    private var _currentAuthorizationStatus: Any?
    
    var isReady: Bool {
        primeIfNeeded()
        return _isReady
    }
    
    /// Check if the user has denied NineAnimator's access to HomeKit data
    var isPermissionDenied: Bool {
        if #available(iOS 13.0, *) {
            // Use cached permission status to check if the permission is denied
            if let status = _currentAuthorizationStatus as? HMHomeManagerAuthorizationStatus {
                return status.contains(.determined) && !status.contains(.authorized)
            } else { return false }
        } else { return false }
    }
    
    private lazy var manager: HMHomeManager = {
        // Creating this object is known to trigger main thread checker
        // But it doesn't seem to affect anything
        Log.info("Initializing HMHomeManager. An error might be thrown, which doesn't seem to affect anything.")
        let manager = HMHomeManager()
        manager.delegate = self
        return manager
    }()
    
    override init() {
        super.init()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPlaybackStart(notification:)),
            name: .playbackDidStart,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPlaybackWillEnd(notification:)),
            name: .playbackWillEnd,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onExternalPlaybackDidStart(notification:)),
            name: .externalPlaybackDidStart,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onExternalPlaybackWillEnd(notification:)),
            name: .externalPlaybackWillEnd,
            object: nil
        )
    }
    
    deinit { NotificationCenter.default.removeObserver(self) }
}

// MARK: - HMHomeManagerDelegate
extension HomeController {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        _isReady = true
        
        if #available(iOS 13.0, *) {
            updateAuthorizationStatus()
        }
        
        NotificationCenter.default.post(name: .homeDidUpdate, object: self)
    }
    
    @available(iOS 13.0, *)
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        updateAuthorizationStatus()
    }
    
    @objc private func onPlaybackStart(notification: Notification) {
        guard NineAnimator.default.user.homeIntegrationRunOnExternalPlaybackOnly == false else {
            return
        }
        
        if let uuid = NineAnimator.default.user.homeIntegrationStartsActionSetUUID {
            run(scene: uuid)
        }
    }
    
    @objc private func onPlaybackWillEnd(notification: Notification) {
        guard NineAnimator.default.user.homeIntegrationRunOnExternalPlaybackOnly == false else {
            return
        }
        
        if let uuid = NineAnimator.default.user.homeIntegrationEndsActionSetUUID {
            run(scene: uuid)
        }
    }
    
    @objc private func onExternalPlaybackDidStart(notification: Notification) {
        guard NineAnimator.default.user.homeIntegrationRunOnExternalPlaybackOnly == true else {
            return
        }
        
        if let uuid = NineAnimator.default.user.homeIntegrationStartsActionSetUUID {
            run(scene: uuid)
        }
    }
    
    @objc private func onExternalPlaybackWillEnd(notification: Notification) {
        guard NineAnimator.default.user.homeIntegrationRunOnExternalPlaybackOnly == true else {
            return
        }
        
        if let uuid = NineAnimator.default.user.homeIntegrationEndsActionSetUUID {
            run(scene: uuid)
        }
    }
}

// MARK: - Accessing HomeController
extension HomeController {
    var availableScenes: [UUID: String] {
        var scenes = [UUID: String]()
        for home in manager.homes {
            for scene in home.actionSets {
                scenes[scene.uniqueIdentifier] = manager.homes.count > 1 ?
                    "\(scene.name) (\(home.name))" : scene.name
            }
        }
        return scenes
    }
    
    func name(forScene uuid: UUID) -> String? {
        actionSet(for: uuid)?.name
    }
    
    func actionSet(for uuid: UUID) -> HMActionSet? {
        let scenes = manager.homes.flatMap { $0.actionSets }
        return scenes.first { $0.uniqueIdentifier == uuid }
    }
    
    /**
     This initialize the HMHomeManager if at least one scene is set to run
     
     Called when AnimeViewController starts retriving episode
     */
    func primeIfNeeded() {
        if NineAnimator.default.user.homeIntegrationEndsActionSetUUID != nil ||
            NineAnimator.default.user.homeIntegrationStartsActionSetUUID != nil {
            prime()
        }
    }
    
    /**
     Initialize the HMHomeManager
     */
    func prime() {
        // Init lazy variable
        _ = self.manager
        
        if #available(iOS 13.0, *) {
            updateAuthorizationStatus()
        }
    }
    
    @available(iOS 13.0, *)
    private func updateAuthorizationStatus() {
        let oldStatus = _currentAuthorizationStatus as? HMHomeManagerAuthorizationStatus
        let newStatus = manager.authorizationStatus
        
        if newStatus != oldStatus {
            _currentAuthorizationStatus = newStatus
            Log.info(
                "[HomeController] Authorization status changed to %@",
                newStatus.rawValue
            )
            NotificationCenter.default.post(
                name: .homeDidReceiveAuthroizationStatus,
                object: self
            )
        }
    }
}

// MARK: - Run Scenes
extension HomeController {
    func run(scene uuid: UUID) {
        Log.info("Searching HomeKit scene with UUID '%@'", uuid.uuidString)
        for home in manager.homes {
            for scene in home.actionSets where scene.uniqueIdentifier == uuid {
                Log.info("Executing HomeKit action set '%@', total actions %@", scene.name, scene.actions.count)
                home.executeActionSet(scene) {
                    error in Log.info("Finished with error: %@", String(describing: error))
                }
            }
        }
    }
}
