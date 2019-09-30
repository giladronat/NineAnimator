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

import Alamofire
import Foundation
import JavaScriptCore
import SwiftSoup

// MARK: - WAF Detection
extension BaseSource {
    /// Detects the presence of a cloudflare WAF verification page
    static func _cloudflareWAFVerificationMiddleware(
        request: URLRequest?,
        response: HTTPURLResponse,
        body: Data?
        ) -> Alamofire.DataRequest.ValidationResult {
        if let requestingUrl = request?.url,
            let serverHeaderField = response.allHeaderFields["Server"] as? String,
            serverHeaderField.lowercased().hasPrefix("cloudflare"),
            let body = body,
            let bodyString = String(data: body, encoding: .utf8),
            bodyString.contains("jschl_vc"),
            bodyString.contains("jschl_answer") {
            // Save the requestingUrl for modification
            var passthroughUrl: URL?
            
            // Parse the necessary components and include that in the error
            do {
                let bowl = try SwiftSoup.parse(bodyString)
                let cfJschlVcValue = try bowl.select("input[name=jschl_vc]").attr("value")
                let cfPassValue = try bowl.select("input[name=pass]").attr("value")
                let cfSValue = try bowl.select("input[name=s]").attr("value")
                let cfJschlAnswerValue = try some(
                    _cloudflareWAFSolveChallenge(bodyString, requestingUrl: requestingUrl),
                    or: .decodeError
                )
                
                guard let challengeScheme = requestingUrl.scheme,
                    let challengeHost = requestingUrl.host,
                    let challengeUrl = URL(string: "\(challengeScheme)://\(challengeHost)/cdn-cgi/l/chk_jschl")
                    else { throw NineAnimatorError.urlError }
                
                // Reconstruct the url with cloudflare challenge value stored in the fragment
                var urlBuilder = URLComponents(url: challengeUrl, resolvingAgainstBaseURL: false)
                var cfQueryFilteredCharacters = CharacterSet.urlFragmentAllowed
                _ = cfQueryFilteredCharacters.remove("/")
                _ = cfQueryFilteredCharacters.remove("=")
                _ = cfQueryFilteredCharacters.remove("+")
                urlBuilder?.percentEncodedQueryItems = [
                    .init(name: "s", value: cfSValue.addingPercentEncoding(withAllowedCharacters: cfQueryFilteredCharacters)),
                    .init(name: "jschl_vc", value: cfJschlVcValue.addingPercentEncoding(withAllowedCharacters: cfQueryFilteredCharacters)),
                    .init(name: "pass", value: cfPassValue.addingPercentEncoding(withAllowedCharacters: cfQueryFilteredCharacters)),
                    .init(name: "jschl_answer", value: cfJschlAnswerValue)
                ]
                
                Log.info("[CF_WAF] Detected a potentially solvable WAF challenge")
                
                // Store passthrough url
                passthroughUrl = try some(urlBuilder?.url, or: .urlError)
            } catch { Log.info("Cannot find all necessary components to solve Cloudflare challenges.") }
            
            return .failure(
                NineAnimatorError.CloudflareAuthenticationChallenge(
                    "The website had asked NineAnimator to verify that you are not an attacker. Please complete the challenge in the opening page. When you are finished, close the page and NineAnimator will attempt to load the resource again.",
                    authenticationUrl: passthroughUrl
                )
            )
        }
        return .success
    }
    
    /// Obtain the jschl_answer field from the challenge page
    ///
    /// ### References
    /// [1] [cloudflare-scrape](https://github.com/Anorov/cloudflare-scrape/blob/master/cfscrape/__init__.py)
    /// [2] [cloudscraper](https://github.com/codemanki/cloudscraper/blob/master/index.js)
    fileprivate static func _cloudflareWAFSolveChallenge(_ challengePageContent: String, requestingUrl: URL) -> String? {
        let jsMatchingRegex = try! NSRegularExpression(
            pattern: "getElementById\\('cf-content'\\)[\\s\\S]+?setTimeout.+?\\r?\\n([\\s\\S]+?a\\.value\\s*=.+?)\\r?\\n(?:[^{<>]*\\},\\s*(\\d{4,}))?",
            options: []
        )
        
        // Obtain the raw resolver portion of the js
        guard var solveJs = jsMatchingRegex.firstMatch(in: challengePageContent)?.firstMatchingGroup else {
            return nil
        }
        
        // Obtain the length of the host
        guard let hostLength = requestingUrl.host?.count else { return nil }
        
        // Directly return the resolved value instead of assigning it to the form
        solveJs = solveJs.replacingOccurrences(
            of: " '; 121'",
            with: "",
            options: [ .regularExpression ]
        )
        
        // Remove some form assignments
        solveJs = solveJs.replacingOccurrences(
            of: "\\s{3,}(?:t|f)(?: = |\\.).+",
            with: "",
            options: [ .regularExpression ]
        )
        
        // Replace `t.length` with the length of the host string
        solveJs = solveJs.replacingOccurrences(
            of: "t.length",
            with: "\(hostLength)"
        )
        
        solveJs = solveJs.replacingOccurrences(
            of: "document\\.getElementById\\('jschl-answer'\\);",
            with: "{ value: 0 }",
            options: [ .regularExpression ]
        )
        
        // Evaluate the javascript and return the value
        // JSContext is a safe and sandboxed environment, so no need to run in vm like node
        let context = JSContext()
        return context?.evaluateScript(solveJs)?.toString()
    }
}

// MARK: - Retry request
extension BaseSource: Alamofire.RequestRetrier {
    func should(_ manager: SessionManager,
                retry request: Request,
                with error: Error,
                completion: @escaping RequestRetryCompletion) {
        // Assign self as the source of error
        if let error = error as? NineAnimatorError {
            error.sourceOfError = self
        }
        
        // Call the completion handler
        func fail() {
            Log.info("[CF_WAF] Failed to resolve cloudflare challenge")
            completion(false, 0)
        }
        
        // Check if there is an cloudflare authentication error
        if let error = error as? NineAnimatorError.CloudflareAuthenticationChallenge,
            let verificationUrl = error.authenticationUrl {
            // Return fail if challenge solver is not enabled
            if !NineAnimator.default.user.solveFirewallChalleges {
                Log.info("[CF_WAF] Encountered a solvable challenge but the autoresolver has been disabled. Falling back to manual authentication.")
                return fail()
            }
            
            // Abort after 2 tries
            if request.retryCount > 1 {
                Log.info("[CF_WAF] Maximal number of retry reached, renewing identity.")
                self.renewIdentity()
                for cookie in HTTPCookieStorage.shared.cookies(for: verificationUrl) ?? [] {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
                return fail()
            }
            
            let delay = 5.0
            Log.info("[CF_WAF] Attempting to solve cloudflare WAF challenge...continues after %@ seconds", delay)
            
            // Solve the challenge in 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let originalUrlString = request.request?.url?.absoluteString
                    else { return fail() }
                
                Log.info("[CF_WAF] Sending cf resolve challenge request...")
                
                // Make the verification request and then call the retry handler
                self.browseSession.request(verificationUrl, headers: [
                    "Referer": originalUrlString,
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                ]) .responseData {
                    value in
                    guard case .success = value.result,
                        let headerFields = value.response?.allHeaderFields as? [String: String]
                        else { return fail() }
                    
                    // Check if clearance has been granted. If not, renew the current identity
                    let verificationResponseCookies = HTTPCookie.cookies(
                        withResponseHeaderFields: headerFields,
                        for: verificationUrl
                    )
                    
                    if verificationResponseCookies.contains(where: { $0.name == "cf_clearance" }) {
                        Log.info("[CF_WAF] Clearance has been granted")
                    }
                    
                    Log.info("[CF_WAF] Resuming original request...")
                    completion(true, 0.2)
                }
            }
            
            // Return without calling the completion handler
            return
        }
        
        // Default to no retry
        fail()
    }
}
