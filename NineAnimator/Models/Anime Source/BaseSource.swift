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

/**
 Class BaseSource: all the network functions that the subclasses will ever need
 */
class BaseSource: SessionDelegate {
    let parent: NineAnimator
    
    var endpoint: String { return "" }
    
    var endpointURL: URL { return URL(string: endpoint)! }
    
    // Default to enabled
    var isEnabled: Bool { return true }
    
    var _cfResolverTimer: Timer?
    var _cfPausedTasks = [Alamofire.RequestRetryCompletion]()
    var _internalUAIdentity = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Safari/605.1.15"
    
    /// The session used to create ajax requests
    lazy var retriverSession: SessionManager = createRetriverSession()
    
    /// The session used to create browsing requests
    lazy var browseSession: SessionManager = createBrowseSession()
    
    /// The user agent that should be used with requests
    var sessionUserAgent: String { return _internalUAIdentity }
    
    /// Middlewares for verification
    private var verificationMiddlewares = [Alamofire.DataRequest.Validation]()
    
    init(with parent: NineAnimator) {
        self.parent = parent
        
        super.init()
        
        // Prevent cloudflare check redirection
        self.taskWillPerformHTTPRedirection = {
            _, _, response, newRequest in
            if response.url?.path == "/cdn-cgi/l/chk_jschl" {
                return nil
            } else { return newRequest }
        }
        // Add cloudflare middleware
        self.addMiddleware(BaseSource._cloudflareWAFVerificationMiddleware)
    }
    
    /**
     Test if the url belongs to this source
     
     The default logic to test if the url belongs to this source is to see if
     the host name of this url ends with the source's endpoint.
     
     Subclasses should override this method if the anime watching url is
     different from the enpoint url.
     */
    func canHandle(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return endpoint.hasSuffix(host)
    }
    
    /// Default `recommendServer(for:)` implementation
    ///
    /// The default recommendation behavior is to find the first streaming
    /// source whose name is registered in the default VideoProviderRegistry
    func recommendServer(for anime: Anime) -> Anime.ServerIdentifier? {
        let availableServers = anime.servers
        return availableServers.first {
            VideoProviderRegistry.default.provider(for: $0.value) != nil
            || VideoProviderRegistry.default.provider(for: $0.key) != nil
        }?.key
    }
    
    /// Default `recommendServers(for, ofPurpose:)` implementation
    ///
    /// This implementation recommend servers by trying to obtain the provider for each server
    /// and check if the provider is being recommended for the specified purpose
    func recommendServers(for anime: Anime, ofPurpose purpose: VideoProviderParser.Purpose) -> [Anime.ServerIdentifier] {
        let availableServers = anime.servers
        let registry = VideoProviderRegistry.default
        
        return availableServers.compactMap {
            // Try to obtain the parser and check if its recommended for the
            // specified purpose
            if let provider = registry.provider(for: $0.value) ?? registry.provider(for: $0.key),
                provider.isParserRecommended(forPurpose: purpose) {
                return $0.key
            } else { return nil }
        }
    }
    
    func request(browse url: URL, headers: [String: String], completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        return applyMiddlewares(
                to: browseSession.request(url, headers: headers)
            ).responseString {
                switch $0.result {
                case .failure(let error):
                    Log.error("request to %@ failed - %@", url, error)
                    handler(nil, error)
                case .success(let value):
                    handler(value, nil)
                }
            }
    }
    
    func request(ajax url: URL, headers: [String: String], completion handler: @escaping NineAnimatorCallback<NSDictionary>) -> NineAnimatorAsyncTask? {
        return applyMiddlewares(
                to: retriverSession.request(url, headers: headers)
            ) .responseJSON {
                response in
                switch response.result {
                case .failure(let error):
                    Log.error("request to %@ failed - %@", url, error)
                    handler(nil, error)
                case .success(let value as NSDictionary):
                    handler(value, nil)
                default:
                    Log.error("Unable to convert response value to NSDictionary")
                    handler(nil, NineAnimatorError.responseError("Invalid Response"))
                }
            }
    }
    
    func request(ajaxString url: URL, headers: [String: String], completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        return applyMiddlewares(
                to: retriverSession.request(url, headers: headers)
            ) .responseString {
                response in
                switch response.result {
                case .failure(let error):
                    Log.error("request to %@ failed - %@", url, error)
                    handler(nil, error)
                case .success(let value):
                    handler(value, nil)
                }
            }
    }
    
    func request(browse path: String, completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        return request(browse: path, with: [:], completion: handler)
    }
    
    func request(browse path: String, with headers: [String: String], completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            Log.error("Unable to parse URL with endpoint \"%@\" at path \"%@\"", endpoint, path)
            handler(nil, NineAnimatorError.urlError)
            return nil
        }
        return request(browse: url, headers: headers, completion: handler)
    }
    
    func request(ajax path: String, completion handler: @escaping NineAnimatorCallback<NSDictionary>) -> NineAnimatorAsyncTask? {
        return request(ajax: path, with: [:], completion: handler)
    }
    
    func request(ajax path: String, with headers: [String: String], completion handler: @escaping NineAnimatorCallback<NSDictionary>) -> NineAnimatorAsyncTask? {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            Log.error("Unable to parse URL with endpoint \"%@\" at path \"%@\"", endpoint, path)
            handler(nil, NineAnimatorError.urlError)
            return nil
        }
        return request(ajax: url, headers: headers, completion: handler)
    }
    
    func request(ajaxString path: String, completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        return request(ajaxString: path, with: [:], completion: handler)
    }
    
    func request(ajaxString path: String, with headers: [String: String], completion handler: @escaping NineAnimatorCallback<String>) -> NineAnimatorAsyncTask? {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            Log.error("Unable to parse URL with endpoint \"%@\" at path \"%@\"", endpoint, path)
            handler(nil, NineAnimatorError.urlError)
            return nil
        }
        return request(ajaxString: url, headers: headers, completion: handler)
    }
}

// MARK: - Validation middlewares
extension BaseSource {
    func addMiddleware(_ middleware: @escaping Alamofire.DataRequest.Validation) {
        verificationMiddlewares.append(middleware)
    }
    
    func applyMiddlewares(to request: Alamofire.DataRequest) -> Alamofire.DataRequest {
        return verificationMiddlewares.reduce(request) { $0.validate($1) }
    }
}

extension BaseSource {
    fileprivate func createRetriverSession() -> SessionManager {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpAdditionalHeaders = [
            "User-Agent": sessionUserAgent,
            "X-Requested-With": "XMLHttpRequest"
        ]
        let manager = SessionManager(configuration: configuration, delegate: self)
        manager.retrier = self
        return manager
    }
    
    fileprivate func createBrowseSession() -> SessionManager {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpAdditionalHeaders = [
            "User-Agent": sessionUserAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        let manager = SessionManager(configuration: configuration, delegate: self)
        manager.retrier = self
        return manager
    }
    
    func renewIdentity() {
        let pool = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Safari/605.1.15",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36",
            "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 11_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 Edge/17.17134"
        ]
        
        // Pick a user agent
        let randomUA = pool[Int.random(in: 0..<pool.count)]
        _internalUAIdentity = randomUA
        
        // Recreate the sessions
        browseSession = createBrowseSession()
        retriverSession = createRetriverSession()
    }
}
