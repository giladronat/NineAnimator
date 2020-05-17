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

class InformationSceneStatisticsTableViewCell: UITableViewCell {
    private var statistics: ListingAnimeStatistics?
    
    @IBOutlet private weak var averageScoreLabel: UILabel!
    @IBOutlet private weak var frequencyChart: FrequencyChartView!
    
    func initialize(_ statistics: ListingAnimeStatistics) {
        self.statistics = statistics
        self.frequencyChart.distribution = statistics.ratingsDistribution
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.maximumSignificantDigits = 3
        formatter.minimumSignificantDigits = 3
        
        self.averageScoreLabel.text = formatter.string(from: NSNumber(value: statistics.meanScore))
    }
}
