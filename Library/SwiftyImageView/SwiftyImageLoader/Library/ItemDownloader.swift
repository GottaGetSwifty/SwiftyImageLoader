//
//  ItemDownloader.swift
//  SwiftyImageLoader
//
//  Created by Paul Fechner on 12/17/17.
//  Copyright © 2017 peejweej.inc. All rights reserved.
//

import Foundation

protocol DataInitializable {
    init?(data: Data)
}
extension UIImage: DataInitializable {
    
}

class ItemDownloader<ItemType: DataInitializable>: Callback {
    
    let url: URL
    let cacheManager: CacheManager<ItemType>
    let placeholder: ItemType?
    
    init(url: URL, cacheManager: CacheManager<ItemType>, placeholder: ItemType? = nil) {
        self.url = url
        self.cacheManager = cacheManager
        self.placeholder = placeholder
    }   
    
    func load(item: ItemType) {
        
    }
    
    func loadPlaceholder() {
        
    }
        
    func cachedResponseIsValid(_ cachedResponse: CachedURLResponse) -> Bool {
     
        guard let creationTimestamp = cachedResponse.userInfo?["creationTimestamp"] as? CFTimeInterval else {
            return false
        }
        let passedTime = Date.timeIntervalSinceReferenceDate - creationTimestamp 
        return passedTime < Double(cacheManager.diskCacheMaxAge)
    }
    
    func isCacheable(_ policy: NSURLRequest.CachePolicy) -> Bool {
        switch policy {
        case .returnCacheDataElseLoad, .returnCacheDataDontLoad:
            return true
        default:
            return false
        }
    }
    
    func responseIsChacheable(for request: URLRequest) -> Bool { 
        guard cacheManager.diskCacheMaxAge > 0 else {
            return false
        } 
        return isCacheable(request.cachePolicy) && isCacheable(cacheManager.session.configuration.requestCachePolicy)
    }
        
    func makeConsumer() -> Consumer<DownloadInfo<ItemType>> {
        return Consumer<DownloadInfo<ItemType>>(callbackItem: self)
    }
            
    func callback(for item: DownloadInfo<ItemType>) {
        
    }
    
    func download() {
            
        let request = URLRequest(url: url, cachePolicy: cacheManager.session.configuration.requestCachePolicy, timeoutInterval: cacheManager.session.configuration.timeoutIntervalForRequest)
        
//        request.addValue("image/*", forHTTPHeaderField: "Accept")
        
        let sharedURLCache = cacheManager.urlCache
        
        // If there's already a cached image, load it into the image view.
        if let item = cacheManager[url] {
            load(item: item)
        }
            // If there's already a cached response, load the image data into the image view.
        else if let cachedResponse = sharedURLCache.cachedResponse(for: request), cachedResponseIsValid(cachedResponse), let item = ItemType(data: cachedResponse.data) {   
            load(item: item)
            cacheManager.updateDownload(to: .finished, for: url, with: item)
        }
        else {
            
            // Remove the stale disk-cached response (if any).
            sharedURLCache.removeCachedResponse(for: request)
            loadPlaceholder()
            
            // If the image isn't already being downloaded, begin downloading the image.
            if cacheManager.isDownloading(from: url){
                cacheManager.add(consumer: makeConsumer(), for: url)
                return
            }
            else {
                downloadItem(with: request)
            }
            
        }
    }
    
    func downloadItem(with request: URLRequest) {
        
        cacheManager.set(downloadingState: .downloading, for: url)
        
        let dataTask = cacheManager.session.dataTask(with: request) { (taskData, taskResponse, taskError) in
            
            guard let data = taskData, let response = taskResponse, let item = ItemType(data: data), taskError == nil else {
                DispatchQueue.main.async {
                    self.cacheManager.set(downloadingState: .failure, for: self.url)
                    //TODO: remove consumer
                }
                
                return
            }
            
            DispatchQueue.main.async {
                
                //This should circle back to us via the Consumer
                self.cacheManager.updateDownload(to: .finished, for: self.url, with: item)
                
                if self.responseIsChacheable(for: request), let httpResponse = response as? HTTPURLResponse {
                    self.cacheManager.cache(response: httpResponse, from: request, with: data)
                }
            }
        }
        
        dataTask.resume()
    }
}


    

