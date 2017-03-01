//
//  Created by Kiavash Faisali on 2015-03-17.
//  Copyright (c) 2015 Kiavash Faisali. All rights reserved.
//

import UIKit

// MARK: - UIImageView Associated Object Keys
private var indexPathIdentifierAssociationKey: UInt8 = 0
private var completionHolderAssociationKey: UInt8 = 0

// MARK: - UIImageView Extension
extension UIImageView {

    // MARK: - Image Loading Methods
    /**
        Asynchronously downloads an image and loads it into the `UIImageView` using a URL `String`.
        
        - parameter urlString: The image URL in the form of a `String`.
        - parameter placeholderImage: `UIImage?` representing a placeholder image that is loaded into the view while the asynchronous download takes place. The default value is `nil`.
        - parameter completion: An optional closure that is called to indicate completion of the intended purpose of this method. It returns two values: the first is a `Bool` indicating whether everything was successful, and the second is `NSError?` which will be non-nil should an error occur. The default value is `nil`.
    */
    final public func loadImage(withString imageURLString: String, placeholder placeholderImage: UIImage? = nil, completion: ImageCompletion? = nil)
    {
        guard let url = URL(string: imageURLString) else {
            DispatchQueue.main.async {
                completion?(false, nil)
            }
            
            return
        }
        
        loadImage(withUrl: url, placeholder: placeholderImage, completion: completion)
    }

    /**
        Asynchronously downloads an image and loads it into the `UIImageView` using a `URL`.
     
        - parameter url: The image `URL`.
        - parameter placeholderImage: `UIImage?` representing a placeholder image that is loaded into the view while the asynchronous download takes place. The default value is `nil`.
        - parameter completion: An optional closure that is called to indicate completion of the intended purpose of this method. It returns two values: the first is a `Bool` indicating whether everything was successful, and the second is `NSError?` which will be non-nil should an error occur. The default value is `nil`.
     */
    final public func loadImage(withUrl imageURL: URL, placeholder placeholderImage: UIImage? = nil, completion: ImageCompletion? = nil)
    {
        let request = SwiftyImageCacheManager.sharedInstance.makeUrlRequest(with: imageURL)
        
        loadImage(withRequest: request, placeholder: placeholderImage, completion: completion)
    }
    
    /**
        Asynchronously downloads an image and loads it into the `UIImageView` using a `URLRequest`.
     
        - parameter request: The image URL in the form of a `URLRequest`.
        - parameter placeholderImage: `UIImage?` representing a placeholder image that is loaded into the view while the asynchronous download takes place. The default value is `nil`.
        - parameter completion: An optional closure that is called to indicate completion of the intended purpose of this method. It returns two values: the first is a `Bool` indicating whether everything was successful, and the second is `NSError?` which will be non-nil should an error occur. The default value is `nil`.
     */
    final public func loadImage(withRequest imageRequest: URLRequest, placeholder placeholderImage: UIImage? = nil, completion: ImageCompletion? = nil) {

        let cacheManager = SwiftyImageCacheManager.sharedInstance
        let fadeAnimationDuration = cacheManager.fadeAnimationDuration
        
        func showImage(_ image: UIImage) {
            UIView.transition(with: self, duration: fadeAnimationDuration, options: .transitionCrossDissolve, animations: {
                self.image = image
            })
        }

        // If there's already a cached image, load it into the image view and call the completion
        if let url = imageRequest.url, let image = cacheManager[url] {
            showImage(image)
            completion?(true, nil)
            return
        }

        //Otherwise we have to load the image. Show the placeholder if it exists
        if let placeholderImage = placeholderImage {
            self.image = placeholderImage
        }

        //Looks like more has to happen. Just send it to the cacher
        cacheManager.findImageOrDownload(with: imageRequest, observer: CachedImageObserver(observing: self, completion: completion, imageLoadedAction: showImage))

        // If there's already a cached response, load the image data into the image view.
//         if let cachedResponse = sharedURLCache.cachedResponse(for: request), let image = UIImage(data: cachedResponse.data), let creationTimestamp = cachedResponse.userInfo?["creationTimestamp"] as? CFTimeInterval, (Date.timeIntervalSinceReferenceDate - creationTimestamp) < Double(cacheManager.diskCacheMaxAge) {
//            loadImage(image)
//
//            cacheManager[urlAbsoluteString] = image
//        }
//        // Either begin downloading the image or become an observer for an existing request.
//        else {
//            // Remove the stale disk-cached response (if any).
//            sharedURLCache.removeCachedResponse(for: request)
//
//            // Set the placeholder image if it was provided.
//            if let image = placeholderImage {
//                self.image = image
//            }
//
//            // If the image isn't already being downloaded, begin downloading the image.
//            if cacheManager.isDownloadingFromURL(urlAbsoluteString) == false {
//                cacheManager.setIsDownloadingFromURL(true, forURLString: urlAbsoluteString)
//
//                let dataTask = cacheManager.session.dataTask(with: request) {
//                    taskData, taskResponse, taskError in
//
//                    guard let data = taskData, let response = taskResponse, let image = UIImage(data: data), taskError == nil else {
//                        DispatchQueue.main.async {
//                            cacheManager.setIsDownloadingFromURL(false, forURLString: urlAbsoluteString)
//                            cacheManager.removeImageCacheObserversForKey(urlAbsoluteString)
//                            self.completionHolder.completion?(false, taskError as NSError?)
//                        }
//
//                        return
//                    }
//
//                    DispatchQueue.main.async {
//                        if initialIndexIdentifier == self.indexPathIdentifier {
//                            UIView.transition(with: self, duration: fadeAnimationDuration, options: .transitionCrossDissolve, animations: {
//                                self.image = image
//                            })
//                        }
//
//                        cacheManager[urlAbsoluteString] = image
//
//                        let responseDataIsCacheable = cacheManager.diskCacheMaxAge > 0 &&
//                            Double(data.count) <= 0.05 * Double(sharedURLCache.diskCapacity) &&
//                            (cacheManager.session.configuration.requestCachePolicy == .returnCacheDataElseLoad ||
//                                cacheManager.session.configuration.requestCachePolicy == .returnCacheDataDontLoad) &&
//                            (request.cachePolicy == .returnCacheDataElseLoad ||
//                                request.cachePolicy == .returnCacheDataDontLoad)
//
//                        if let httpResponse = response as? HTTPURLResponse, let url = httpResponse.url, responseDataIsCacheable {
//                            if var allHeaderFields = httpResponse.allHeaderFields as? [String: String] {
//                                allHeaderFields["Cache-Control"] = "max-age=\(cacheManager.diskCacheMaxAge)"
//                                if let cacheControlResponse = HTTPURLResponse(url: url, statusCode: httpResponse.statusCode, httpVersion: "HTTP/1.1", headerFields: allHeaderFields) {
//                                    let cachedResponse = CachedURLResponse(response: cacheControlResponse, data: data, userInfo: ["creationTimestamp": Date.timeIntervalSinceReferenceDate], storagePolicy: .allowed)
//                                    sharedURLCache.storeCachedResponse(cachedResponse, for: request)
//                                }
//                            }
//                        }
//
//                        self.completionHolder.completion?(true, nil)
//                    }
//                }
//
//                dataTask.resume()
//            }
//            // Since the image is already being downloaded and hasn't been cached, register the image view as a cache observer.
//            else {
//                weak var weakSelf = self
//                cacheManager.addImageCacheObserver(weakSelf!, withInitialIndexIdentifier: initialIndexIdentifier, forKey: urlAbsoluteString)
//            }
//        }
    }
}
