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

extension Optional {
    /// Try to unwrap the optional value, or throw an error
    ///
    /// Why? This makes chaining much easier and simpler to write & read
    func tryUnwrap(_ error: @autoclosure () -> NineAnimatorError = .decodeError) throws -> Wrapped {
        switch self {
        case let .some(value): return value
        default: throw error()
        }
    }
    
    /// Run the closure with the value if there is a value in this optional
    func unwrap<ResultType>(_ ifUnwrapped: (Wrapped) throws -> ResultType) rethrows -> ResultType? {
        switch self {
        case let .some(value): return try ifUnwrapped(value)
        default: return nil
        }
    }
}

// MARK: Optional<URL>
extension Optional where Wrapped == URL {
    func tryUnwrap() throws -> Wrapped {
        try tryUnwrap(.urlError)
    }
}
