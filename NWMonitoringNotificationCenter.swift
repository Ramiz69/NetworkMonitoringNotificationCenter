//
//  NWMonitoringNotificationCenter.swift
//  Eargasm
//
//  Created by Рамиз Кичибеков on 12.11.2023.
//  Copyright © 2023 Рамиз Кичибеков. All rights reserved.
//

import Foundation

protocol NWMonitoringObserverProtocol: AnyObject, Sendable {
    var identifier: AnyHashable { get }
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter)
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter) async
}

extension NWMonitoringObserverProtocol {
    
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter) {
        
    }
    
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter) async {
        
    }
    
}

protocol NWMonitoringNotificationCenterProtocol: AnyObject, Sendable {
    func add(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name)
    func remove(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name)
    func post(event: Notification.Name, object: NWMonitoringManagerProtocol)
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool
    
    func addAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async
    func removeAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async
    func postAsync(event: Notification.Name, object: NWMonitoringManagerProtocol) async
    func hasObserverAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async -> Bool
}

fileprivate actor NWMonitoringObserver {
    private var observers = [String: [AnyHashable: WeakObserver]]()
    
    func addObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        let weakObserver = WeakObserver(observer)
        observers[event.rawValue, default: [:]][observer.identifier] = weakObserver
    }
    
    func removeObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        observers[event.rawValue]?.removeValue(forKey: observer.identifier)
    }
    
    func post(forEvent event: Notification.Name, with object: NWMonitoringManagerProtocol) async {
        guard let values = observers[event.rawValue]?.values else { return }
        
        for observer in values {
            await observer.observer?.observe(event: event,
                                             monitorManager: object,
                                             notificationCenter: NWMonitoringNotificationCenter.shared)
        }
    }
    
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool {
        return observers[event.rawValue]?.keys.contains(observer.identifier) ?? false
    }
}

final class NWMonitoringNotificationCenter: NWMonitoringNotificationCenterProtocol {
    
    // MARK: - Properties
    
    static let shared = NWMonitoringNotificationCenter()
    private let observerManager = NWMonitoringObserver()
    private var observers = [String: [AnyHashable: WeakObserver]]()
    private var lock = pthread_rwlock_t()
    private let networkMonitoringManager: NWMonitoringManagerProtocol = NWMonitoringManager.shared
    
    // MARK: - Life cycle
    
    private init() {
        pthread_rwlock_init(&lock, nil)
        networkMonitoringManager.startMonitoring()
    }
    
    func asyncInitiate() async {
        Task {
            await networkMonitoringManager.startMonitoringAsync()
        }
    }
    
    deinit {
        pthread_rwlock_destroy(&lock)
        networkMonitoringManager.stopMonitoring()
    }
    
    // MARK: - Public methods
    
    func add(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        let weakObserver = WeakObserver(observer)
        
        pthread_rwlock_wrlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        observers[event.rawValue, default: [:]][observer.identifier] = weakObserver
    }
    
    func remove(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        pthread_rwlock_wrlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        observers[event.rawValue]?.removeValue(forKey: observer.identifier)
    }
    
    func post(event: Notification.Name, object: NWMonitoringManagerProtocol) {
        pthread_rwlock_rdlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        observers[event.rawValue]?.values.forEach {
            $0.observer?.observe(event: event, monitorManager: object, notificationCenter: self)
        }
    }
    
    // MARK: Swift Concurrency
    
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool {
        pthread_rwlock_rdlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        return observers[event.rawValue]?.keys.contains(observer.identifier) ?? false
    }
    
    func addAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async {
        await observerManager.addObserver(observer, forEvent: event)
    }
    
    func removeAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async {
        await observerManager.removeObserver(observer, forEvent: event)
    }
    
    func postAsync(event: Notification.Name, object: NWMonitoringManagerProtocol) async {
        await observerManager.post(forEvent: event, with: object)
    }
    
    func hasObserverAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async -> Bool {
        return await observerManager.hasObserver(observer, forEvent: event)
    }
    
}

fileprivate class WeakObserver {
    weak var observer: NWMonitoringObserverProtocol?
    
    init(_ observer: NWMonitoringObserverProtocol) {
        self.observer = observer
    }
}
