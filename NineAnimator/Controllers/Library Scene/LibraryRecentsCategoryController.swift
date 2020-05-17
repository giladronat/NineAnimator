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

import UIKit

class LibraryRecentsCategoryController: MinFilledCollectionViewController, LibraryCategoryReceiverController {
    /// Cached recent anime from `NineAnimatorUser`
    private var cachedRecentAnime = [AnimeLink]()
    
    /// The `AnimeLink` that was selected by the user in the collection view
    private var selectedAnimeLink: AnimeLink?
    
    /// The `IndexPath` that is currently used by the menu controller
    private var menuIndexPath: IndexPath?
    
    /// Needs to be able to become the first responder
    override var canBecomeFirstResponder: Bool { true }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize Min Filled Layout
        setLayoutParameters(
            alwaysFillLine: false,
            minimalSize: .init(width: 300, height: 110)
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Load Recent Links
        self.reloadRecentLinks()
    }
}

// MARK: - Data Loading
extension LibraryRecentsCategoryController {
    private func reloadRecentLinks() {
        let shouldAnimate = self.cachedRecentAnime.isEmpty
        self.cachedRecentAnime = NineAnimator.default.user.recentAnimes
        
        // Send message to the collection view
        if shouldAnimate {
            self.collectionView.reloadSections([ 0 ])
        } else { self.collectionView.reloadData() }
    }
    
    /// Remove the anime from the recents anime list
    private func removeAnime(atIndex indexPath: IndexPath) {
        DispatchQueue.main.async {
            self.cachedRecentAnime.remove(at: indexPath.item)
            self.collectionView.deleteItems(at: [ indexPath ])
            NineAnimator.default.user.recentAnimes = self.cachedRecentAnime
        }
    }
}

// MARK: - Data Source & Delegate
extension LibraryRecentsCategoryController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? cachedRecentAnime.count : 0
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "recents.item",
            for: indexPath
        ) as! LibraryRecentAnimeCell
        cell.setPresenting(cachedRecentAnime[indexPath.item])
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        selectedAnimeLink = cachedRecentAnime[indexPath.item]
        performSegue(withIdentifier: "recents.player", sender: cell)
    }
}

// MARK: - Initialization
extension LibraryRecentsCategoryController {
    func setPresenting(_ category: LibrarySceneController.Category) {
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.largeTitleTextAttributes[.foregroundColor] = category.tintColor
            navigationItem.scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Navigation
extension LibraryRecentsCategoryController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Initialize the anime viewer
        if let destination = segue.destination as? AnimeViewController,
            let selectedAnimeLink = selectedAnimeLink {
            destination.setPresenting(anime: selectedAnimeLink)
        }
    }
}

// MARK: - Context Menu & Editing
extension LibraryRecentsCategoryController {
    /// For iOS 13.0 and higher, use the built-in `UIContextMenu` for operations
    @available(iOS 13.0, *)
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let animationWaitTime: DispatchTimeInterval = .milliseconds(500)
        let relatedAnimeLink = cachedRecentAnime[indexPath.item]
        let configuration = UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil) {
                [weak self] _ -> UIMenu? in
                var menuItems = [UIAction]()
                
                // Subscription
                if NineAnimator.default.user.isSubscribing(anime: relatedAnimeLink) {
                    menuItems.append(.init(
                        title: "Unsubscribe",
                        image: UIImage(systemName: "bell.slash.fill"),
                        identifier: nil
                    ) { _ in NineAnimator.default.user.unsubscribe(anime: relatedAnimeLink) })
                } else {
                    menuItems.append(.init(
                        title: "Subscribe",
                        image: UIImage(systemName: "bell.fill"),
                        identifier: nil
                    ) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + animationWaitTime) {
                            // Request permission first
                            UserNotificationManager.default.requestNotificationPermissions()
                            NineAnimator.default.user.subscribe(uncached: relatedAnimeLink)
                        }
                    })
                }
                
                // Share
                menuItems.append(.init(
                    title: "Share",
                    image: UIImage(systemName: "square.and.arrow.up"),
                    identifier: nil
                ) { _ in
                    // Wait for 0.5 second until presenting
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationWaitTime) {
                        guard let self = self,
                            let cell = self.collectionView.cellForItem(at: indexPath) else {
                                return
                        }
                        
                        // Present the share sheet
                        RootViewController.shared?.presentShareSheet(
                            forLink: .anime(relatedAnimeLink),
                            from: cell,
                            inViewController: self
                        )
                    }
                })
                
                // Remove
                menuItems.append(.init(
                    title: "Remove from Recents",
                    image: UIImage(systemName: "trash.fill"),
                    identifier: nil,
                    attributes: [ .destructive ]
                ) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationWaitTime) {
                        self?.removeAnime(atIndex: indexPath)
                    }
                })
                
                return UIMenu(
                    title: "Selected Anime",
                    identifier: nil,
                    options: [],
                    children: menuItems
                )
            }
        return configuration
    }
    
    @IBAction private func onLongPressGestureRegconized(_ sender: UILongPressGestureRecognizer) {
        if #available(iOS 13.0, *) {
            // Not doing anything for iOS 13.0+ since
            // actions are presented with context menus
        } else if sender.state == .began {
            let location = sender.location(in: collectionView)
            // Obtain the cell
            if let indexPath = collectionView.indexPathForItem(at: location),
                let cell = collectionView.cellForItem(at: indexPath) as? LibraryRecentAnimeCell {
                self.becomeFirstResponder()
                
                self.menuIndexPath = indexPath
                let targetRect = collectionView.convert(cell.frame, to: view)
                let editMenu = UIMenuController.shared
                var availableMenuItems = [UIMenuItem]()
                
                // Remove operation
                availableMenuItems.append(.init(
                    title: "Remove",
                    action: #selector(menuController(removeLink:))
                ))
                
                // Save the available actions
                editMenu.menuItems = availableMenuItems
                editMenu.setTargetRect(targetRect, in: view)
                editMenu.setMenuVisible(true, animated: true)
            }
        }
    }
    
    @objc private func menuController(removeLink sender: UIMenuController) {
        if let menuIndexPath = menuIndexPath {
            removeAnime(atIndex: menuIndexPath)
        }
    }
}
