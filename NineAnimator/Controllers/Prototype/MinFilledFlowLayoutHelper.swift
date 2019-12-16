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

import UIKit

/// A layout helper for building a minimal size based line filled collection view
///
/// A few steps to adapt this helper
/// - Add the class variable `var layoutHelper = MinFilledFlowLayoutHelper(...)`
/// - Configure the collection view using `layoutHelper.configure(collectionView: collectionView)` on `viewDidLoad`
/// - Forward `viewWillTransition()` and `viewWillAppear()` events to the helper
class MinFilledFlowLayoutHelper: NSObject, UICollectionViewDelegateFlowLayout {
    typealias LineLayoutParameters = (
        ordinary: CGSize,
        lastLine: CGSize,
        lastLineOffset: Int,
        ordinaryLineUnitCount: Int,
        lastLineUnitCount: Int,
        numberOfLines: Int
    )
    
    /// Data source for the collection view
    private weak var dataSource: UICollectionViewDataSource?
    
    /// Minimal size for a given cell
    private var minimalSizes: [CGSize]
    
    /// Bounds for the cached layouts
    private var previousSpace: CGSize
    
    /// Cached layout parameters
    private var cachedLayoutParameters: [Int: LineLayoutParameters]
    
    /// If the cells should always fill the line space
    private var alwaysFillLine: Bool
    
    convenience init(dataSource: UICollectionViewDataSource, alwaysFillLine: Bool, minimalSize: CGSize...) {
        self.init(
            dataSource: dataSource,
            alwaysFillLine: alwaysFillLine,
            minimalSizes: minimalSize
        )
    }
    
    init(dataSource: UICollectionViewDataSource, alwaysFillLine: Bool, minimalSizes: [CGSize]) {
        // Store parameters
        self.dataSource = dataSource
        self.minimalSizes = minimalSizes
        self.previousSpace = .zero
        self.cachedLayoutParameters = [:]
        self.alwaysFillLine = alwaysFillLine
        
        super.init()
    }
    
    func configure(collectionView: UICollectionView) {
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.estimatedItemSize = .zero
            layout.sectionInsetReference = .fromLayoutMargins
            collectionView.contentInsetAdjustmentBehavior = .always
        }
    }
    
    /// Call from `viewWillTransition`
    func viewWillTransition(coordinator: UIViewControllerTransitionCoordinator, in collectionView: UICollectionView) {
        coordinator.animate(alongsideTransition: {
            _ in
            collectionView.performBatchUpdates({
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.setNeedsLayout()
            }, completion: nil)
            collectionView.layoutIfNeeded()
        }, completion: nil)
    }
    
    /// Call from `viewWillAppear`
    func viewWillAppear(_ collectionView: UICollectionView) {
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let layout = layout as? UICollectionViewFlowLayout else {
            Log.error("[MinFilledFlowLayoutHelper] This delegate can only be used with FlowLayout.")
            return .zero
        }
        
        guard dataSource != nil else {
            Log.error("[MinFilledFlowLayoutHelper] Lost reference to the data source.")
            return .zero
        }
        
        let availableSpace = self.availableSpace(for: collectionView, inSection: indexPath.section)
        
        // Clears layout cache when bounds change
        if availableSpace != previousSpace {
            clearLayoutCache()
            previousSpace = availableSpace
        }
        
        // Obtain the calculated layout parameters
        let parameters = cachedLayoutParameters[indexPath.section] ?? calculateLayoutParameters(
            view: collectionView,
            layout: layout,
            section: indexPath.section
        )
        
        // Obtain the unit parameters
        let unitParameters = layoutParameters(
            forIndex: indexPath,
            inCollection: collectionView,
            parameters: parameters
        )
        let resultingSize: CGSize
        
        // If the item is not in the last line or the fill line option is not enabled,
        // always returns the ordinal size
        if indexPath.item < parameters.lastLineOffset
            || !shouldFillLine(collectionView, for: indexPath.section) {
            resultingSize = parameters.ordinary
        } else if shouldAlignLastLine(collectionView, for: indexPath.section) {
            // If the alignment option is enabled, return normal size for all except
            // the last cell in the last line
            if unitParameters.item == unitParameters.itemsInLine - 1 {
                resultingSize = .init(
                    width: (parameters.lastLine.width * CGFloat(unitParameters.itemsInLine))
                        - parameters.ordinary.width * CGFloat(unitParameters.itemsInLine - 1),
                    height: (parameters.lastLine.height * CGFloat(unitParameters.itemsInLine))
                        - parameters.ordinary.height * CGFloat(unitParameters.itemsInLine - 1)
                )
            } else { resultingSize = parameters.ordinary }
        } else { resultingSize = parameters.lastLine } // Else returns the last line size
        
        // Make delegate calls
        if let minFilledDelegate = collectionView.delegate as? MinFilledLayoutDelegate {
            // Call the delegate method
            minFilledDelegate.minFilledLayout?(
                collectionView,
                didLayout: indexPath,
                withParameters: unitParameters
            )
        }
        
        return resultingSize
    }
    
    /// Obtain the cached layout attributes for `indexPath`
    func layoutParameters(forIndex indexPath: IndexPath, inCollection collectionView: UICollectionView) -> LayoutParameters? {
        if let parameters = cachedLayoutParameters[indexPath.section] {
            return layoutParameters(
                forIndex: indexPath,
                inCollection: collectionView,
                parameters: parameters
            )
        }
        
        return nil
    }
    
    /// Obtain the unit layout parameters calculated based on line parameters
    private func layoutParameters(forIndex indexPath: IndexPath, inCollection collectionView: UICollectionView, parameters: LineLayoutParameters) -> LayoutParameters {
        let parameterItemsCount = shouldFillLine(collectionView, for: indexPath.section)
            ? ( // Filling line, returning the last line unit count for last line
                indexPath.item < parameters.lastLineOffset
                    ? parameters.ordinaryLineUnitCount : parameters.lastLineUnitCount
            ) : parameters.ordinaryLineUnitCount
        return LayoutParameters(
            item: indexPath.item % parameters.ordinaryLineUnitCount,
            line: indexPath.item / parameters.ordinaryLineUnitCount,
            itemsInLine: parameterItemsCount,
            numberOfLines: parameters.numberOfLines
        )
    }
    
    /// Forcefully clear the cached layouts for each element
    ///
    /// Layout cache is automatically cleared when the bounds changes
    func clearLayoutCache() {
        cachedLayoutParameters = [:]
    }
    
    /// Recalculate the layout parameters
    private func calculateLayoutParameters(view: UICollectionView, layout: UICollectionViewFlowLayout, section: Int) -> LineLayoutParameters {
        guard let dataSource = dataSource else { return (.zero, .zero, 0, 0, 0, 0) }
        
        let availableUnits = dataSource.collectionView(view, numberOfItemsInSection: section)
        
        guard availableUnits > 0 else { return (.zero, .zero, 0, 0, 0, 0) }
        
        let availableSpace = self.availableSpace(for: view, inSection: section)
        let variableParameter: WritableKeyPath<CGSize, CGFloat> =
            layout.scrollDirection == .vertical ? \.width : \.height
        let fixedParameter: WritableKeyPath<CGSize, CGFloat> =
            layout.scrollDirection == .vertical ? \.height : \.width
        
        let totalLength = availableSpace[keyPath: variableParameter]
        let unitMinimal = minimalSize(for: section)[keyPath: variableParameter]
        let interitemSpace = interitemSpacing(for: view, layout: layout, section: section)
        
        // Calculate unit length
        let ordinalLineUnits = ordinalCellsPerLine(
            minimal: unitMinimal,
            totalLength: totalLength,
            interitemSpace: interitemSpace
        )
        let (ordinaryCount, ordinalLength) = unitParameter(
            minimal: unitMinimal,
            available: .max,
            totalLength: totalLength,
            interitemSpace: interitemSpace
        )
        let (lastLineCount, lastLineLength) = unitParameter(
            minimal: unitMinimal,
            available: availableUnits % ordinalLineUnits,
            totalLength: totalLength,
            interitemSpace: interitemSpace
        )
        
        // Create three different sizes
        var resultingSize = CGSize()
        resultingSize[keyPath: fixedParameter] = minimalSize(for: section)[keyPath: fixedParameter]
        
        var ordinalSize = resultingSize
        ordinalSize[keyPath: variableParameter] = ordinalLength
        
        var lastLineSize = resultingSize
        lastLineSize[keyPath: variableParameter] = lastLineLength
        
        // Generate and cache result
        let result = (
            ordinalSize,
            lastLineSize,
            availableUnits / ordinalLineUnits * ordinalLineUnits,
            ordinaryCount,
            lastLineCount,
            Int(ceil(Double(availableUnits) / Double(ordinalLineUnits)))
        )
        cachedLayoutParameters[section] = result
        return result
    }
    
    /// Calculate the cell size parameters
    private func unitParameter(minimal: CGFloat, available: Int, totalLength: CGFloat, interitemSpace: CGFloat) -> (count: Int, length: CGFloat) {
        let realisticMinimal = (0.00001...totalLength).clamp(value: minimal)
        let count = min(floor((totalLength + interitemSpace) / (realisticMinimal + interitemSpace)), CGFloat(available))
        let length = (totalLength - count * interitemSpace + interitemSpace) / count
        return (Int(count), length - 0.001)
    }
    
    /// Calculate the number of cells per line assuming the remaining cells are enough to fill the entire space
    private func ordinalCellsPerLine(minimal: CGFloat, totalLength: CGFloat, interitemSpace: CGFloat) -> Int {
        return unitParameter(
            minimal: minimal,
            available: .max,
            totalLength: totalLength,
            interitemSpace: interitemSpace
        ).count
    }
    
    /// Minimal Size
    private func minimalSize(for section: Int) -> CGSize {
        return minimalSizes[min(section, minimalSizes.count - 1)]
    }
    
    private func shouldFillLine(_ collectionView: UICollectionView, for section: Int) -> Bool {
        var result = alwaysFillLine
        if let delegate = collectionView.delegate as? MinFilledLayoutDelegate {
            result = delegate.minFilledLayout?(collectionView, shouldFillLineForSection: section) ?? result
        }
        return result
    }
    
    private func shouldAlignLastLine(_ collectionView: UICollectionView, for section: Int) -> Bool {
        return (collectionView.delegate as? MinFilledLayoutDelegate)?.minFilledLayout?(
            collectionView,
            shouldAlignLastLineItemsInSection: section
        ) ?? false
    }
    
    private func interitemSpacing(for collectionView: UICollectionView, layout: UICollectionViewFlowLayout, section: Int) -> CGFloat {
        var result = layout.minimumInteritemSpacing
        if let delegate = collectionView.delegate as? UICollectionViewDelegateFlowLayout {
            result = delegate.collectionView?(
                collectionView,
                layout: layout,
                minimumInteritemSpacingForSectionAt: section
            ) ?? result
        }
        return result
    }
    
    private func sectionInset(for collectionView: UICollectionView, layout: UICollectionViewFlowLayout, section: Int) -> UIEdgeInsets {
        var result = layout.sectionInset
        if let delegate = collectionView.delegate as? UICollectionViewDelegateFlowLayout {
            result = delegate.collectionView?(
                collectionView,
                layout: layout,
                insetForSectionAt: section
            ) ?? result
        }
        return result
    }
    
    private func availableSpace(for collectionView: UICollectionView, inSection section: Int) -> CGSize {
        var availableSpace = collectionView.bounds
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            availableSpace = availableSpace
                .inset(by: sectionInset(for: collectionView, layout: layout, section: section))
                .inset(by: collectionView.layoutMargins)
        }
        return availableSpace.size
    }
}

extension MinFilledFlowLayoutHelper {
    class LayoutParameters: NSObject {
        var item: Int
        var line: Int
        var itemsInLine: Int
        var numberOfLines: Int
        
        init(item: Int, line: Int, itemsInLine: Int, numberOfLines: Int) {
            self.item = item
            self.line = line
            self.itemsInLine = itemsInLine
            self.numberOfLines = numberOfLines
        }
    }
}

@objc protocol MinFilledLayoutDelegate {
    @objc optional func minFilledLayout(_ collectionView: UICollectionView, didLayout indexPath: IndexPath, withParameters: MinFilledFlowLayoutHelper.LayoutParameters)
    
    @objc optional func minFilledLayout(_ collectionView: UICollectionView, shouldFillLineForSection section: Int) -> Bool
    
    @objc optional func minFilledLayout(_ collectionView: UICollectionView, shouldAlignLastLineItemsInSection section: Int) -> Bool
}
