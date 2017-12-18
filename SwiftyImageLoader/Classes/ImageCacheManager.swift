//
//  Created by Kiavash Faisali on 2015-03-17.
//  Copyright (c) 2015 Kiavash Faisali. All rights reserved.
//

import UIKit
import MapKit
import WatchKit

// MARK: - ImageCacheKeys Struct
fileprivate struct ImageCacheKeys {
    static let image = "image"
    static let isDownloading = "isDownloading"
    static let observerMapping = "observerMapping"
}

enum DownloadState { 
    case none
    case downloading
    case finished
    case failure
    
}

protocol ImageDownloadConsumer: AnyObject {
    func callback(for download: ImageDownload)
}

// object to keep track of a download
internal class ImageDownload: Hashable {
    var hashValue: Int {
        return url.hashValue
    }
    
    let url: URL
    var state: DownloadState
    var observers: [ImageDownloadConsumer]
    var image: UIImage? = nil
    
    init(url: URL, observers: [ImageDownloadConsumer] = [], state: DownloadState = .none) {
        self.state = state
        self.url = url
        self.observers = observers
    }
    
    func remove(observer: ImageDownloadConsumer) {
        if let foundIndex = observers.index(where: { $0 === observer }) {
            observers.remove(at: foundIndex)
        }
    }
    
    func add(observer: ImageDownloadConsumer) {
        if(!observers.contains(where: {$0 === observer})) {
            observers.append(observer)
        }
    }
    
    func notifyObservers() {
        observers.forEach { $0.callback(for: self)}
    }
    
    static func ==(left: ImageDownload, right: ImageDownload) -> Bool {
        return left.url == right.url
    }
}

private class ImageDownloadManager {
    
    private var downloads: [URL : ImageDownload] = [:]
    
    internal subscript (key: URL) -> ImageDownload {
        if let foundItem = downloads[key] {
            return foundItem
        }
        else {
            let newItem = ImageDownload(url: key)
            downloads[key] = newItem
            return newItem
        }
    }
    
    func add(observer: ImageDownloadConsumer, for url: URL) {
        downloads.values.forEach() {
            if $0.url != url {
                $0.remove(observer: observer)
            } 
        }
        self[url].add(observer: observer)
    }
}

// MARK: - ImageChacheManager Class
final public class ImageCacheManager {
    // MARK: - Properties
    public static let sharedInstance = ImageCacheManager()
    
    private var urlCache: URLCache
    private var downloadManager = ImageDownloadManager()
    
    // {"url": {"img": UIImage, "isDownloading": Bool, "observerMapping": {Observer: Int}}}
    fileprivate var imageCache = [String: [String: AnyObject]]()
    
    internal lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = .shared
        
        return URLSession(configuration: configuration)
    }()
    
    /**
        Sets the fade duration time (in seconds) for images when they are being loaded into their views.
        A value of 0 implies no fade animation.
        The default value is 0.1 seconds.
        
        - returns: An NSTimeInterval value representing time in seconds.
    */
    public var fadeAnimationDuration: TimeInterval = 0.1
    
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
    static let memoryCapacity = 50 * 1024 * 1024
    static let diskCapacity = 100 * 1024 * 1024
    fileprivate init() {
        // Initialize the disk cache capacity to 100 MB.
        let diskURLCache = URLCache(memoryCapacity: ImageCacheManager.memoryCapacity, diskCapacity: ImageCacheManager.diskCapacity, diskPath: nil)
        self.urlCache = diskURLCache
        
        NotificationCenter.default.addObserver(forName: .UIApplicationDidReceiveMemoryWarning, object: nil, queue: .main) {
            _ in
            self.imageCache.removeAll(keepingCapacity: false)
        }
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    internal subscript (key: URL) -> UIImage? {
        get {
            return downloadManager[key].image
        }
    }
    
    func updateDownload(to state: DownloadState, for url: URL, with image: UIImage?) {
        downloadManager[url].state = state
        downloadManager[url].image = image
        downloadManager[url].notifyObservers()
    }

    // MARK: - Image Cache Subscripting
    internal subscript (key: String) -> UIImage? {
        get {
            return imageCacheEntryForKey(key)[ImageCacheKeys.image] as? UIImage
        }
        set {
            if let image = newValue {
                var imageCacheEntry = imageCacheEntryForKey(key)
                imageCacheEntry[ImageCacheKeys.image] = image
                setImageCacheEntry(imageCacheEntry, forKey: key)
                
                if let observerMapping = imageCacheEntry[ImageCacheKeys.observerMapping] as? [NSObject: Int] {
                    for (observer, initialIndexIdentifier) in observerMapping {
                        switch observer {
                        case let imageView as UIImageView:
                            loadObserver(imageView, image: image, initialIndexIdentifier: initialIndexIdentifier)
                        case let button as UIButton:
                            loadObserver(button, image: image, initialIndexIdentifier: initialIndexIdentifier)
                        case let annotationView as MKAnnotationView:
                            loadObserver(annotationView, image: image)
                        case let interfaceImage as WKInterfaceImage:
                            loadObserver(interfaceImage, image: image, key: key)
                        default:
                            break
                        }
                    }

                    removeImageCacheObserversForKey(key)
                }
            }
        }
    }
    
    // MARK: - Image Cache Methods
    internal func imageCacheEntryForKey(_ key: String) -> [String: AnyObject] {
        if let imageCacheEntry = self.imageCache[key] {
            return imageCacheEntry
        }
        else {
            let imageCacheEntry: [String: AnyObject] = [ImageCacheKeys.isDownloading: false as AnyObject, ImageCacheKeys.observerMapping: [NSObject: Int]() as AnyObject]
            self.imageCache[key] = imageCacheEntry
            
            return imageCacheEntry
        }
    }
    
    internal func setImageCacheEntry(_ imageCacheEntry: [String: AnyObject], forKey key: String) {
        self.imageCache[key] = imageCacheEntry
    }
    
    internal func isDownloadingFromURL(_ urlString: String) -> Bool {
        let isDownloading = imageCacheEntryForKey(urlString)[ImageCacheKeys.isDownloading] as? Bool
        
        return isDownloading ?? false
    }
    
    internal func setIsDownloadingFromURL(_ isDownloading: Bool, forURLString urlString: String) {
        var imageCacheEntry = imageCacheEntryForKey(urlString)
        imageCacheEntry[ImageCacheKeys.isDownloading] = isDownloading as AnyObject?
        setImageCacheEntry(imageCacheEntry, forKey: urlString)
    }
    
    internal func addImageCacheObserver(_ observer: NSObject, withInitialIndexIdentifier initialIndexIdentifier: Int, forKey key: String) {
        var imageCacheEntry = imageCacheEntryForKey(key)
        if var observerMapping = imageCacheEntry[ImageCacheKeys.observerMapping] as? [NSObject: Int] {
            observerMapping[observer] = initialIndexIdentifier
            imageCacheEntry[ImageCacheKeys.observerMapping] = observerMapping as AnyObject?
            setImageCacheEntry(imageCacheEntry, forKey: key)
        }
    }
    
    internal func removeImageCacheObserversForKey(_ key: String) {
        var imageCacheEntry = imageCacheEntryForKey(key)
        if var observerMapping = imageCacheEntry[ImageCacheKeys.observerMapping] as? [NSObject: Int] {
            observerMapping.removeAll(keepingCapacity: false)
            imageCacheEntry[ImageCacheKeys.observerMapping] = observerMapping as AnyObject?
            setImageCacheEntry(imageCacheEntry, forKey: key)
        }
    }
    
    // MARK: - Observer Methods
    internal func loadObserver(_ imageView: UIImageView, image: UIImage, initialIndexIdentifier: Int) {
        if initialIndexIdentifier == imageView.indexPathIdentifier {
            DispatchQueue.main.async {
                UIView.transition(with: imageView,
                              duration: self.fadeAnimationDuration,
                               options: .transitionCrossDissolve,
                            animations: {
                    imageView.image = image
                })
                
                imageView.completionHolder.completion?(true, nil)
            }
        }
        else {
            imageView.completionHolder.completion?(false, nil)
        }
    }
    
    internal func loadObserver(_ button: UIButton, image: UIImage, initialIndexIdentifier: Int) {
        if initialIndexIdentifier == button.indexPathIdentifier {
            DispatchQueue.main.async {
                UIView.transition(with: button,
                              duration: self.fadeAnimationDuration,
                               options: .transitionCrossDissolve,
                            animations: {
                    if button.isBackgroundImage == true {
                        button.setBackgroundImage(image, for: button.controlStateHolder.controlState)
                    }
                    else {
                        button.setImage(image, for: button.controlStateHolder.controlState)
                    }
                })
                
                button.completionHolder.completion?(true, nil)
            }
        }
        else {
            button.completionHolder.completion?(false, nil)
        }
    }
    
    internal func loadObserver(_ annotationView: MKAnnotationView, image: UIImage) {
        DispatchQueue.main.async {
            UIView.transition(with: annotationView,
                          duration: self.fadeAnimationDuration,
                           options: .transitionCrossDissolve,
                        animations: {
                annotationView.image = image
            })
            
            annotationView.completionHolder.completion?(true, nil)
        }
    }
    
    internal func loadObserver(_ interfaceImage: WKInterfaceImage, image: UIImage, key: String) {
        DispatchQueue.main.async {
            // If there's already a cached image on the Apple Watch, simply set the image directly.
            if WKInterfaceDevice.current().cachedImages[key] != nil {
                interfaceImage.setImageNamed(key)
            }
            else {
                interfaceImage.setImageData(UIImagePNGRepresentation(image))
            }
            
            interfaceImage.completionHolder.completion?(true, nil)
        }
    }
}
