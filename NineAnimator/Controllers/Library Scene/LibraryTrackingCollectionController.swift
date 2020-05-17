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

class LibraryTrackingCollectionController: MinFilledCollectionViewController, ContentProviderDelegate {
    private var collection: LibrarySceneController.Collection?
    private var cachedCollectionReferences = NSMutableOrderedSet()
    private var selectedReference: ListingAnimeReference?
    private var referencesToContextsMap = [ListingAnimeReference: [TrackingContext]]()
    private var referencesMappingQueue = DispatchQueue.global()
    private var loadedReferencesPages = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize Min Filled Layout
        setLayoutParameters(
            alwaysFillLine: false,
            minimalSize: .init(width: 300, height: 130)
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard collection != nil else {
            return Log.error("[LibraryTrackingCollectionController] Collection has not been set while the view is already appearing. Has this controller been initialized?")
        }
        
        // Set delegate
        collection!.delegate = self
        
        // Start loading pages
        if collection!.availablePages == 0 {
            collection!.more()
        } else {
            // Update the collection references
            loadedReferencesPages = collection!.availablePages
            cachedCollectionReferences = (0..<loadedReferencesPages).reduce(into: NSMutableOrderedSet()) {
                cache, page in cache.addObjects(
                    from: collection!.links(on: page).compactMap(asListingReference)
                )
            }
            collectionView.reloadData()
        }
    }
}

// MARK: - Init & Data Loading
extension LibraryTrackingCollectionController {
    /// Initialize this controller with a tracking collection
    func setPresenting(_ trackingCollection: LibrarySceneController.Collection) {
        self.collection = trackingCollection
        self.title = trackingCollection.title
    }
    
    /// Handling page available event
    ///
    /// This method redirects the message to `onPageAvailable` on the main thread.
    func pageIncoming(_ page: Int, from provider: ContentProvider) {
        DispatchQueue.main.async {
            [weak self] in self?.onPageAvailable(page, from: provider)
        }
    }
    
    private func onPageAvailable(_ page: Int, from provider: ContentProvider) {
        // Cache collection references
        let cachedPageReferences = provider
            .links(on: page)
            .compactMap(asListingReference)
        
        // If this page has already been loaded, reload and dedupe all pages
        if page < loadedReferencesPages {
            Log.info("[LibraryTrackingCollectionController] Attempting to load page %@ when it has been loaded. Reloading all pages.", page)
            cachedCollectionReferences = (0..<provider.availablePages).reduce(into: NSMutableOrderedSet()) {
                cache, page in cache.addObjects(
                    from: provider.links(on: page).map(asListingReference)
                )
            }
            collectionView.reloadSections([ 0 ])
            loadedReferencesPages = provider.availablePages // Update page variable
        } else { // Else just append this to the end
            // Insert to the cachedReferences and notify the collection view
            let additionalIndicies = cachedPageReferences.reduce(into: [IndexPath]()) {
                results, reference in
                if !cachedCollectionReferences.contains(reference) {
                    results.append(.init(
                        item: cachedCollectionReferences.count,
                        section: 0
                    ))
                    cachedCollectionReferences.add(reference)
                }
            }
            collectionView.insertItems(at: additionalIndicies)
            loadedReferencesPages = page + 1
        }
        
        // Load related contexts
        fetchTrackingContexts(forReferences: cachedPageReferences)
        loadMoreIfNeeded() // Load more if still at the bottom of the page
    }
    
    func onError(_ error: Error, from provider: ContentProvider) {
        Log.error("[LibraryTrackingCollectionController] Received error from Collection Source: @%", error)
    }
    
    private func fetchTrackingContexts(forReferences references: [ListingAnimeReference]) {
        // Asynchronously execute the mapping task to prevent blocking the main thread
        referencesMappingQueue.async {
            [weak self] in
            // Fetch the contexts related to the references
            var additionalReferencesMap = [ListingAnimeReference: [TrackingContext]]()
            for reference in references {
                additionalReferencesMap[reference] = NineAnimator.default.trackingContexts(containingReference: reference)
            }
            
            // Synchronously save the fetched contexts to the global map
            DispatchQueue.main.sync {
                guard let self = self else { return }
                self.referencesToContextsMap = additionalReferencesMap
                    .reduce(into: self.referencesToContextsMap) {
                        $0[$1.key] = $1.value
                    }
                self.didResolveAdditonalReferencesMap()
            }
        }
    }
    
    private func didResolveAdditonalReferencesMap() {
        // Only update visible items
        for visibleCellIndex in collectionView.indexPathsForVisibleItems {
            guard let visibleCell = collectionView.cellForItem(at: visibleCellIndex),
                let reference = reference(at: visibleCellIndex),
                let contexts = referencesToContextsMap[reference] else {
                continue
            }
            
            // Call the didResolve methods of the cells to update the subtitle tag
            if let visibleCell = visibleCell as? LibraryTrackingReferenceCell {
                visibleCell.didResolve(relatedTrackingContexts: contexts)
            } else if let visibleCell = visibleCell as? LibraryUntrackedReferenceCell {
                visibleCell.didResolve(relatedTrackingContexts: contexts)
            }
        }
    }
}

// MARK: - Data Source & Delegate
extension LibraryTrackingCollectionController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        loadMoreIfNeeded()
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? cachedCollectionReferences.count : 0
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Obtain the reference from the cached pool
        guard let reference = reference(at: indexPath) else {
            Log.error("[LibraryTrackingCollectionController] UI component tried to load a reference that does not exist: %@", indexPath)
            return UICollectionViewCell()
        }
        let relatedContexts = referencesToContextsMap[reference]
        
        // If this is a tracking anime
        if let tracking = reference.parentService.progressTracking(for: reference) {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "collection.tracking",
                for: indexPath
            ) as! LibraryTrackingReferenceCell
            cell.setPresenting(reference, tracking: tracking, delegate: self)
            
            // If related contexts have been resolved
            if let contexts = relatedContexts {
                cell.didResolve(relatedTrackingContexts: contexts)
            }
            
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "collection.untracked",
                for: indexPath
            ) as! LibraryUntrackedReferenceCell
            cell.setPresenting(reference, delegate: self)
            
            // If related contexts have been resolved
            if let contexts = relatedContexts {
                cell.didResolve(relatedTrackingContexts: contexts)
            }
            
            return cell
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let reference = self.reference(at: indexPath),
            let cell = collectionView.cellForItem(at: indexPath) else {
            return Log.error("[LibraryTrackingCollectionController] Reference does not exist at %@", indexPath)
        }
        
        self.selectedReference = reference
        self.performSegue(withIdentifier: "collection.information", sender: cell)
    }
    
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        cell.makeThemable()
    }
    
    /// Loat more if the view has already been scrolled to the bottom
    private func loadMoreIfNeeded() {
        if let collection = collection, collection.moreAvailable {
            let height = collectionView.frame.size.height
            let contentYoffset = collectionView.contentOffset.y
            let distanceFromBottom = collectionView.contentSize.height - contentYoffset
            
            // Try to load more pages if we're too close to the bottom
            if distanceFromBottom < (2.5 * height) {
                // Calling load more on the original collection reference
                self.collection?.more()
            }
        }
    }
}

extension LibraryTrackingCollectionController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? AnimeInformationTableViewController,
            let reference = self.selectedReference {
            destination.setPresenting(reference: reference)
        }
    }
}

// MARK: - Helper Methods
extension LibraryTrackingCollectionController {
    func reference(at indexPath: IndexPath) -> ListingAnimeReference? {
        indexPath.section == 0 && indexPath.item < cachedCollectionReferences.count
            ? cachedCollectionReferences.object(at: indexPath.item) as? ListingAnimeReference : nil
    }
    
    func asListingReference(_ genericLink: AnyLink) -> ListingAnimeReference? {
        switch genericLink {
        case let .listingReference(reference): return reference
        default: return nil
        }
    }
}
