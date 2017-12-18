//
//  Created by Kiavash Faisali on 2015-03-17.
//  Copyright (c) 2015 Kiavash Faisali. All rights reserved.
//

import UIKit
import MapKit
import WatchKit

// MARK: - ImageCacheKeys Struct
fileprivate enum ImageCacheKeys: String {
    case image
    case isDownloading
    case observerMapping
}

enum SaveState: Equatable{
    case none
    case downloading
    case saved
    case error(Error)

    static func ==(lhs: SaveState, rhs: SaveState) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.downloading, .downloading), (.saved, .saved):
            return true
        default:
            return false
        }
    }
}

class CachedImageObserver {
    private weak var _observingObject: AnyObject?
    var observingObject: AnyObject? {
        return _observingObject
    }
    let observingCompletion: ImageCompletion?
    let imageLoadedAction: (UIImage) -> ()

    init(observing observingObject: AnyObject, completion observingCompletion: ImageCompletion?, imageLoadedAction: @escaping (UIImage) -> ()) {
        self._observingObject = observingObject
        self.observingCompletion = observingCompletion
        self.imageLoadedAction = imageLoadedAction
    }
}

fileprivate class SwiftyImageLoaderCachedImage: Hashable {

	public var hashValue: Int {
		return imageURL.hashValue
	}

    var image: UIImage? {
        didSet {
            if image != nil {
                saveState = .saved
            }
        }
    }
    var saveState: SaveState {
        didSet {
            switch saveState {
            case .saved:
                updateObserversIfComplete()
            case .error(let error):
                finished(with: error)
            default:
                break
            }
        }
    }

    var imageURL: URL
    private var observers: [CachedImageObserver]


    init(with image: UIImage?, for url: URL, saveState: SaveState, observers: [CachedImageObserver]) {
        self.image = image
        self.imageURL = url
        self.saveState = saveState
        self.observers = observers
    }

    fileprivate func updateObserversIfComplete() {

		guard let image = image, saveState == .saved  else {
            return
        }

		//This should make a copy so we don't do anything with this object's actual observers in the async block
		let observerReference = observers

		DispatchQueue.main.async {
			observerReference.forEach({
				$0.imageLoadedAction(image)
				$0.observingCompletion?(true, nil)
			})
		}

		observers.removeAll(keepingCapacity: false)
    }

    fileprivate func finished(with error: Error) {

		//This should make a copy so we don't do anything with this object's actual observers in the async block
		let observerReference = observers

		DispatchQueue.main.async {
			observerReference.forEach({
				$0.observingCompletion?(false, error)
			})
		}

		self.observers.removeAll(keepingCapacity: false)
    }

    func contains(observer comparingObserver: CachedImageObserver) -> Bool {

        for observer in observers {
            if comparingObserver.observingObject === observer.observingObject {
                return true
            }
        }
        return false
    }

    func remove(observer removingObserver: CachedImageObserver) -> Bool {

        let index = observers.index() { $0.observingObject === removingObserver.observingObject }
        if let index = index {
            observers.remove(at: index)
            return true
        }
        else {
            return false
        }
    }

    /// Add an observer for the image
    ///
    /// - Returns: True if added, false if it's already an observer
    @discardableResult func add(observer newObserver: CachedImageObserver) -> Bool {

        guard observers.index(where: { $0.observingObject === newObserver.observingObject }) == nil else {
            return false
        }
        observers.append(newObserver)
        return true
    }

    static func ==(leftItem: SwiftyImageLoaderCachedImage, rightItem: SwiftyImageLoaderCachedImage) -> Bool {
        return leftItem.imageURL == rightItem.imageURL
    }
}

// MARK: - SwiftyImageLoader Class
final public class SwiftyImageCacheManager {
    // MARK: - Properties
    public static let sharedInstance = SwiftyImageCacheManager()

    fileprivate var cachedImages: Set<SwiftyImageLoaderCachedImage> = []

    private var sharedURLCache: URLCache {
        return URLCache.shared
    }
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
    public var diskCacheMaxAge: TimeInterval = 60 * 60 * 24 * 7 {
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
            self.session.configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        }
    }
    
    /**
        Sets the cache policy which the default requests and underlying session configuration use to determine caching behaviour.
        The default value is `returnCacheDataElseLoad`.
        
        - returns: An NSURLRequestCachePolicy value representing the cache policy.
    */
    public var requestCachePolicy = NSURLRequest.CachePolicy.returnCacheDataElseLoad {
        didSet {
            self.session.configuration.requestCachePolicy = requestCachePolicy
        }
    }

	private var observer: Any? = nil
    fileprivate init() {
        // Initialize the disk cache capacity to 50 MB.
        let diskURLCache = URLCache(memoryCapacity: 0, diskCapacity: 50 * 1024 * 1024, diskPath: nil)
        URLCache.shared = diskURLCache

        observer = NotificationCenter.default.addObserver(forName: .UIApplicationDidReceiveMemoryWarning, object: nil, queue: .main) {[weak self] _ in
			//TODO: This should probably be changed to only remove images are aren't currently downloading.
            self?.cachedImages.removeAll()
        }
    }
    deinit {
		guard let observer = observer else {
			return
		}
        NotificationCenter.default.removeObserver(observer)
    }

    func makeUrlRequest(with url: URL) -> URLRequest {

        var request = URLRequest(url: url, cachePolicy: session.configuration.requestCachePolicy, timeoutInterval: session.configuration.timeoutIntervalForRequest)
        request.addValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Image Cache Subscripting
    internal subscript (key: URL) -> UIImage? {
        get {
            return cachedImages.first { $0.imageURL == key }?.image
        }
    }

    func findImageOrDownload(with urlRequest: URLRequest, observer cachedImageObserver: CachedImageObserver) {

        guard let requestURL = urlRequest.url else {
            cachedImageObserver.observingCompletion?(false, ImageLoadingError.improperUrl)
            return
        }

        let currentCachedImage = cachedImages.first(where: { $0.imageURL == requestURL})

        //Case where image is already loaded, just add the observer and update it to saved. this should never be necessary, but just in case
        if let currentCachedImage = currentCachedImage, currentCachedImage.image != nil {
            currentCachedImage.add(observer: cachedImageObserver)
            currentCachedImage.saveState = .saved
            return
        }

        // Try and load the image from the cache
        if let cachedResponse = sharedURLCache.cachedResponse(for: urlRequest), let image = UIImage(data: cachedResponse.data), let creationTimestamp = cachedResponse.userInfo?["creationTimestamp"] as? CFTimeInterval, (Date().timeIntervalSince1970  - creationTimestamp) < diskCacheMaxAge {

            // If the CachedImage objected existed, simply update it and prompt to update
            if let currentCachedImage = currentCachedImage {
                currentCachedImage.add(observer: cachedImageObserver)
                currentCachedImage.image = image
                return
            }

            //otherwise, add a new cached image and prompt for update.
            let newCachedImage = SwiftyImageLoaderCachedImage(with: image, for: requestURL, saveState: .saved, observers: [cachedImageObserver])
            cachedImages.insert(newCachedImage)
            newCachedImage.updateObserversIfComplete()
            return
        }

        // Download is ongoing, just add the new observer.
        if let currentCachedImage = currentCachedImage, currentCachedImage.saveState == .downloading {
            currentCachedImage.add(observer: cachedImageObserver)
            return
        }

        //Update or add the existing image
        if let currentCachedImage = currentCachedImage {
            currentCachedImage.add(observer: cachedImageObserver)
        }
        else {
            let newCachedImage = SwiftyImageLoaderCachedImage(with: nil, for: requestURL, saveState: .downloading, observers: [cachedImageObserver])
            cachedImages.insert(newCachedImage)
        }



        let dataTask = session.dataTask(with: urlRequest) { [weak self] taskData, taskResponse, taskError in
            guard let strongSelf = self else {
                assertionFailure("data task no longer has a reference to self. it done broked.")
                return
            }
            guard let currentCachedImage = self?.cachedImages.first(where: { $0.imageURL == requestURL}) else {
                assertionFailure("Data task returned with no associated cached image. This shouldn't happen")
                return
            }

            guard let data = taskData, let response = taskResponse, let image = UIImage(data: data), taskError == nil else {
                let error = taskError ?? ImageLoadingError.downloadError

                //This should be all that's necessary to notify the observers
                currentCachedImage.saveState = .error(error)
                return
            }

            strongSelf.cacheImageIfNecessary(for: urlRequest, with: data, and: response)

            //this should take care of notifying all the observers
            currentCachedImage.image = image
        }

        dataTask.resume()
    }

    private func cacheImageIfNecessary(for urlRequest: URLRequest, with data: Data, and response: URLResponse) {

        let cachePolicy = session.configuration.requestCachePolicy
        let responseDataIsCacheable = diskCacheMaxAge > 0 && Double(data.count) <= 0.05 * Double(sharedURLCache.diskCapacity) &&
                (cachePolicy == .returnCacheDataElseLoad || cachePolicy == .returnCacheDataDontLoad) &&
                (urlRequest.cachePolicy == .returnCacheDataElseLoad ||  urlRequest.cachePolicy == .returnCacheDataDontLoad)

        // Cache the data if we need to
        guard let httpResponse = response as? HTTPURLResponse, let url = httpResponse.url, responseDataIsCacheable, var allHeaderFields = httpResponse.allHeaderFields as? [String: String]  else {
            return
        }
        allHeaderFields["Cache-Control"] = "max-age=\(diskCacheMaxAge)"

        guard let cacheControlResponse = HTTPURLResponse(url: url, statusCode: httpResponse.statusCode, httpVersion: "HTTP/1.1", headerFields: allHeaderFields) else {
            return
        }
        let cachedResponse = CachedURLResponse(response: cacheControlResponse, data: data, userInfo: ["creationTimestamp": Date.timeIntervalSinceReferenceDate], storagePolicy: .allowed)
        sharedURLCache.storeCachedResponse(cachedResponse, for: urlRequest)
    }

    
    // MARK: - Image Cache Methods
//    internal func getImageCacheEntryForKey(_ key: String) -> [String: AnyObject] {
//        if let imageCacheEntry = self.imageCache[key] {
//            return imageCacheEntry
//        }
//        else {
//            let imageCacheEntry: [String: AnyObject] = [ImageCacheKeys.isDownloading: false as AnyObject, ImageCacheKeys.observerMapping: [NSObject: Int]() as AnyObject]
//            self.imageCache[key] = imageCacheEntry
//
//            return imageCacheEntry
//        }
//    }
//
//    internal func setImageCacheEntry(_ imageCacheEntry: [String: AnyObject], forKey key: String) {
//        self.imageCache[key] = imageCacheEntry
//    }
//
//    internal func isDownloadingFromURL(_ urlString: String) -> Bool {
//        let isDownloading = imageCacheEntryForKey(urlString)[ImageCacheKeys.isDownloading] as? Bool
//
//        return isDownloading ?? false
//    }
//
//    internal func setIsDownloadingFromURL(_ isDownloading: Bool, forURLString urlString: String) {
//        var imageCacheEntry = imageCacheEntryForKey(urlString)
//        imageCacheEntry[ImageCacheKeys.isDownloading] = isDownloading as AnyObject?
//        setImageCacheEntry(imageCacheEntry, forKey: urlString)
//    }
//
//    internal func addImageCacheObserver(_ observer: NSObject, withInitialIndexIdentifier initialIndexIdentifier: Int, forKey key: String) {
//        var imageCacheEntry = imageCacheEntryForKey(key)
//        if var observerMapping = imageCacheEntry[ImageCacheKeys.observerMapping] as? [NSObject: Int] {
//            observerMapping[observer] = initialIndexIdentifier
//            imageCacheEntry[ImageCacheKeys.observerMapping] = observerMapping as AnyObject?
//            setImageCacheEntry(imageCacheEntry, forKey: key)
//        }
//    }
//
//    internal func removeImageCacheObserversForKey(_ key: String) {
//        var imageCacheEntry = imageCacheEntryForKey(key)
//        if var observerMapping = imageCacheEntry[ImageCacheKeys.observerMapping] as? [NSObject: Int] {
//            observerMapping.removeAll(keepingCapacity: false)
//            imageCacheEntry[ImageCacheKeys.observerMapping] = observerMapping as AnyObject?
//            setImageCacheEntry(imageCacheEntry, forKey: key)
//        }
//    }
//
//    // MARK: - Observer Methods
//    internal func loadObserver(_ imageView: UIImageView, image: UIImage, initialIndexIdentifier: Int) {
//        if initialIndexIdentifier == imageView.indexPathIdentifier {
//            DispatchQueue.main.async {
//                UIView.transition(with: imageView,
//                              duration: self.fadeAnimationDuration,
//                               options: .transitionCrossDissolve,
//                            animations: {
//                    imageView.image = image
//                })
//
//                imageView.completionHolder.completion?(true, nil)
//            }
//        }
//        else {
//            imageView.completionHolder.completion?(false, nil)
//        }
//    }
//
//    internal func loadObserver(_ button: UIButton, image: UIImage, initialIndexIdentifier: Int) {
//        if initialIndexIdentifier == button.indexPathIdentifier {
//            DispatchQueue.main.async {
//                UIView.transition(with: button,
//                              duration: self.fadeAnimationDuration,
//                               options: .transitionCrossDissolve,
//                            animations: {
//                    if button.isBackgroundImage == true {
//                        button.setBackgroundImage(image, for: button.controlStateHolder.controlState)
//                    }
//                    else {
//                        button.setImage(image, for: button.controlStateHolder.controlState)
//                    }
//                })
//
//                button.completionHolder.completion?(true, nil)
//            }
//        }
//        else {
//            button.completionHolder.completion?(false, nil)
//        }
//    }
//
//    internal func loadObserver(_ annotationView: MKAnnotationView, image: UIImage) {
//        DispatchQueue.main.async {
//            UIView.transition(with: annotationView,
//                          duration: self.fadeAnimationDuration,
//                           options: .transitionCrossDissolve,
//                        animations: {
//                annotationView.image = image
//            })
//
//            annotationView.completionHolder.completion?(true, nil)
//        }
//    }
//
//    internal func loadObserver(_ interfaceImage: WKInterfaceImage, image: UIImage, key: String) {
//        DispatchQueue.main.async {
//            // If there's already a cached image on the Apple Watch, simply set the image directly.
//            if WKInterfaceDevice.current().cachedImages[key] != nil {
//                interfaceImage.setImageNamed(key)
//            }
//            else {
//                interfaceImage.setImageData(UIImagePNGRepresentation(image))
//            }
//
//            interfaceImage.completionHolder.completion?(true, nil)
//        }
//    }
}
