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

extension Kitsu {
    struct User {
        let name: String
        let identifier: String
    }
    
    func currentUser() -> NineAnimatorPromise<User> {
        // If there is a cached user, return that
        if let user = _cachedUser {
            return .firstly { user }
        }
        
        // Request currently logged in user
        return apiRequest("/users", query: [
            "filter[self]": "true",
            "fields[users]": "name"
        ]) .then {
            [weak self] in
            guard let userObject = $0.first else {
                throw NineAnimatorError.responseError("No response object found")
            }
            
            guard let name = userObject.attributes["name"] as? String else {
                throw NineAnimatorError.decodeError
            }
            
            Log.info("[Kitsu.io] Currently logged in user is %@", name)
            
            // Create and save the user
            let user = User(name: name, identifier: userObject.identifier)
            self?._cachedUser = user
            return user
        }
    }
}
