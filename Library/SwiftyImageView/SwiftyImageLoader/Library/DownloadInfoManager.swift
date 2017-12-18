//
//  DownloadManager.swift
//  SwiftyImageLoader
//
//  Created by Paul Fechner Jr. on 12/17/17.
//  Copyright © 2017 peejweej.inc. All rights reserved.
//

import Foundation


/// Simple download state enum
/// TODO: should add a progress option
/// TODO: should add an Error for .failure
///
/// - none: This should only be set when a download hasn't started
/// - downloading: State for when the download is currently happening
/// - finished: State for when the download is finished
/// - failure: State when the download failed
enum DownloadState { 
    case none
    case downloading
    case finished
    case failure    
}


/// Simple callback protocol
protocol Callback {
    associatedtype T
    func callback(for item: T)
}



/// Container class to make possible the use of callbacks to Types from within generic classes
///
/// Keeps a weak reference to item passed in init
/// If that reference is nil, any receieved callbacks are cancled
class Consumer<ItemType>: Callback {
    
    typealias T = ItemType
    weak private(set) var callingItem: AnyObject?
    private let callbackFunction: (ItemType) -> ()
    
    
    /// Primary Initalizer
    ///
    /// - Parameter callbackItem: The instance of a Class that will receieve the callback.
    ///                           A weak reference is kept so we can cancel callbacks if it's nil 
    ///
    init<T: Callback>(callbackItem: T)  where T.T == ItemType, T: AnyObject {
        callingItem = callbackItem
        self.callbackFunction = callbackItem.callback
    }
    
    /// Calls the callbackFunction of the item passed in init
    ///
    /// - Parameter item: The item being updated
    func callback(for item: ItemType) {
        if callingItem != nil {
            self.callbackFunction(item)
        }
    }
}


/// Class to keep track of download info
/// 
///
/// - Warning:  The Hashable and equatable value is linked directly to the url
internal class DownloadInfo<ItemType>: Hashable {
    
    var hashValue: Int {
        return url.hashValue
    }
    typealias ConsumerType = Consumer<DownloadInfo<ItemType>>
    let url: URL
    var state: DownloadState {
        didSet {
            notifyConsumers()
        }
    }
    var item: ItemType? = nil
    var consumers: [ConsumerType]
    
    /// - Parameters:
    ///   - url: The url being downloaded
    ///   - consumers: Any consumers for state updates (defaults to [])
    ///   - state: the current state of the download (defaults to .none)
    required init(url: URL, consumers: [ConsumerType] = [], state: DownloadState = .none) {
        self.state = state
        self.url = url
        self.consumers = consumers
    }
    
    /// Removes the consumer
    ///
    /// - Parameter consumer: the consumer to remove
    func remove(consumer: ConsumerType) {
        if let foundIndex = consumers.index(where: { $0 === consumer }) {
            consumers.remove(at: foundIndex)
        }
    }
    
    /// Adds a consumer
    ///
    /// - Parameter consumer: The consumer to add
    func add(consumer: ConsumerType) {
        if(!consumers.contains(where: {$0 === consumer})) {
            consumers.append(consumer)
        }
    }
    
    
    /// calls the callback for each consumer with self as a parameter
    func notifyConsumers() {
        consumers.forEach { $0.callback(for: self)}
    }
    
    static func ==<T>(left: DownloadInfo<T>, right: DownloadInfo<T>) -> Bool {
        return left.url == right.url
    }
}



/// Class for managing the info for multiple downloads at the same time.
class DownloadInfoManager<ItemType> {
    typealias InfoType = DownloadInfo<ItemType>
    private var downloads: [URL : InfoType] = [:]
    
        
    /// Gets or creates DownloadInfo for url
    ///
    /// - Parameter key: the url for the desired DownloadInfo
    internal subscript (key: URL) -> InfoType {
        if let foundItem = downloads[key] {
            return foundItem
        }
        else {
            let newItem = InfoType(url: key)
            downloads[key] = newItem
            return newItem
        }
    }
    
    /// Adds a consumer to get callbacks for the url
    ///
    /// - Parameters:
    ///   - consumer: A new consumer for the url
    ///   - url: the url for which the consumer needs to consume updates
    func add(consumer: InfoType.ConsumerType, for url: URL) {
        downloads.values.forEach() {
            if $0.url != url {
                $0.remove(consumer: consumer)
            } 
        }
        self[url].add(consumer: consumer)
    }
    
    
    
    /// Removes any completed downloads
    func removeCompleted() {
        downloads = downloads.filter {
            switch $0.value.state {
            case .finished, .failure:
                $0.value.notifyConsumers()
                return false
            case .none, .downloading:
                return true
            }
        }
    }
}
