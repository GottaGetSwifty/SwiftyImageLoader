//
//  CacheManager.swift
//  SwiftyImageLoader
//
//  Created by Paul Fechner on 12/17/17.
//  Copyright © 2017 peejweej.inc. All rights reserved.
//

import Foundation

final class ImageCacheManager: CacheManager<UIImage> {
    public static let sharedInstance = ImageCacheManager()
}

// MARK: - ImageChacheManager Class
class CacheManager<ItemType>{
    // MARK: - Properties
    
    var urlCache: URLCache
    private var downloadManager = DownloadInfoManager<ItemType>()
    
    internal lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = .shared
        return URLSession(configuration: configuration)
    }()
    
    /**
     Sets the maximum time (in seconds) that the disk cache will use to maintain a cached response.
     The default value is 604800 seconds (1 week).
     
     - returns: An unsigned integer value representing time in seconds.
     */
    public var diskCacheMaxAge: UInt = 60 * 60 * 24 * 7 {
        didSet {
            if diskCacheMaxAge == 0 {
                URLCache.shared.removeAllCachedResponses()
            }
        }
    }
    
    /**
     Sets the maximum time (in seconds) that the request should take before timing out.
     The default value is 60 seconds.
     
     - returns: An NSTimeInterval value representing time in seconds.
     */
    public var timeoutIntervalForRequest: TimeInterval = 60.0 {
        didSet {
            let configuration = self.session.configuration
            configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
            self.session = URLSession(configuration: configuration)
        }
    }
    
    /**
     Sets the cache policy which the default requests and underlying session configuration use to determine caching behaviour.
     The default value is `returnCacheDataElseLoad`.
     
     - returns: An NSURLRequestCachePolicy value representing the cache policy.
     */
    public var requestCachePolicy = NSURLRequest.CachePolicy.returnCacheDataElseLoad {
        didSet {
            let configuration = self.session.configuration
            configuration.requestCachePolicy = requestCachePolicy
            self.session = URLSession(configuration: configuration)
        }
    }
    
    let memoryCapacity = 50 * 1048576
    let diskCapacity = 100 * 1048576
    fileprivate init() {
        // Initialize the disk cache capacity to 100 MB.
        let diskURLCache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: nil)
        self.urlCache = diskURLCache
        
        NotificationCenter.default.addObserver(forName: .UIApplicationDidReceiveMemoryWarning, object: nil, queue: .main) {
            _ in
            self.downloadManager.removeCompleted()
        }
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func cache(response: HTTPURLResponse, from request: URLRequest, with data: Data) {
        guard  let url = response.url, var allHeaderFields = response.allHeaderFields as? [String: String] else {
            return
        }
        
        allHeaderFields["Cache-Control"] = "max-age=\(diskCacheMaxAge)"
        
        guard let cacheControlResponse = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: allHeaderFields) else {
            return
        }
        
        let cachedResponse = CachedURLResponse(response: cacheControlResponse, data: data, userInfo: ["creationTimestamp": Date.timeIntervalSinceReferenceDate], storagePolicy: .allowed)
        urlCache.storeCachedResponse(cachedResponse, for: request)
    }
    
    internal subscript (key: URL) -> ItemType? {
        get {
            return downloadManager[key].item
        }
    }
    
    func updateDownload(to state: DownloadState, for url: URL, with item: ItemType?) {
        downloadManager[url].state = state
        downloadManager[url].item = item
        downloadManager[url].notifyConsumers()
    }
    
    internal func isDownloading(from url: URL) -> Bool {
        let isDownloading = downloadManager[url].state == .downloading
        return isDownloading
    }
    
    internal func set(downloadingState: DownloadState, for url: URL) {
        downloadManager[url].state = downloadingState
    }
    
    internal func add(consumer: Consumer<DownloadInfo<ItemType>>, for url: URL) {
        self.downloadManager[url].add(consumer: consumer)
    }
    
    internal func remove(consumer: Consumer<DownloadInfo<ItemType>>, for url: URL) {
        self.downloadManager[url].remove(consumer: consumer)
    }
}
