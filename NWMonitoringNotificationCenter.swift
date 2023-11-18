//
//  NWMonitoringNotificationCenter.swift
//  Eargasm
//
//  Created by Рамиз Кичибеков on 12.11.2023.
//  Copyright © 2023 Рамиз Кичибеков. All rights reserved.
//

import Foundation

struct NWMonitoringConfigurator: Identifiable {
    
    typealias ID = Int
    
    enum NotifyType {
        case `default`
        case whenConnectionChanged
    }
    
    static let `default` = NWMonitoringConfigurator(id: .zero, notifyType: .default)
    
    var id: ID
    let notifyType: NotifyType
    
    init(id: ID, notifyType: NotifyType) {
        self.id = id
        self.notifyType = notifyType
    }
    
}

protocol NWMonitoringObserverProtocol: AnyObject, Sendable {
    var configurator: NWMonitoringConfigurator { get }
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManager,
                 notificationCenter: NWMonitoringNotificationCenter)
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManager,
                 notificationCenter: NWMonitoringNotificationCenter) async
}

extension NWMonitoringObserverProtocol {
    
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManager,
                 notificationCenter: NWMonitoringNotificationCenter) {
        
    }
    
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManager,
                 notificationCenter: NWMonitoringNotificationCenter) async {
        
    }
    
}

protocol NWMonitoringNotificationCenterProtocol: AnyObject, Sendable {
    func add(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name)
    func remove(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name)
    func post(event: Notification.Name, object: NWMonitoringManager)
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool
    
    func asyncInitiate() async
    func addAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async
    func removeAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async
    func postAsync(event: Notification.Name, object: NWMonitoringManager) async
    func hasObserverAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async -> Bool
}

fileprivate actor NWMonitoringObserver {
    private var observers = [String: [AnyHashable: WeakObserver]]()
    
    func addObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        let weakObserver = WeakObserver(observer)
        observers[event.rawValue, default: [:]][observer.configurator.id] = weakObserver
    }
    
    func removeObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        observers[event.rawValue]?.removeValue(forKey: observer.configurator.id)
    }
    
    func post(forEvent event: Notification.Name, with object: NWMonitoringManager) async {
        guard let values = observers[event.rawValue]?.values else { return }
        
        for value in values {
            guard let observer = value.observer else { return }
            
            let notifyType = observer.configurator.notifyType
            switch notifyType {
            case .default:
                await observer.observe(event: event,
                                       monitorManager: object,
                                       notificationCenter: NWMonitoringNotificationCenter.shared)
            case .whenConnectionChanged:
                if object.connectionChanged {
                    await observer.observe(event: event,
                                           monitorManager: object,
                                           notificationCenter: NWMonitoringNotificationCenter.shared)
                }
            }
        }
    }
    
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool {
        return observers[event.rawValue]?.keys.contains(observer.configurator.id) ?? false
    }
}

final class NWMonitoringNotificationCenter: NWMonitoringNotificationCenterProtocol {
    
    // MARK: - Properties
    
    static let shared = NWMonitoringNotificationCenter()
    private let observerManager = NWMonitoringObserver()
    private var observers = [String: [AnyHashable: WeakObserver]]()
    private var lock = pthread_rwlock_t()
    private let networkMonitoringManager = NWMonitoringManager.shared
    
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
        
        observers[event.rawValue, default: [:]][observer.configurator.id] = weakObserver
    }
    
    func remove(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) {
        pthread_rwlock_wrlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        observers[event.rawValue]?.removeValue(forKey: observer.configurator.id)
    }
    
    func post(event: Notification.Name, object: NWMonitoringManager) {
        pthread_rwlock_rdlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        observers[event.rawValue]?.values.forEach {
            guard let observer = $0.observer else { return }
            
            let notifyType = observer.configurator.notifyType
            switch notifyType {
            case .default:
                observer.observe(event: event, monitorManager: object, notificationCenter: self)
            case .whenConnectionChanged:
                if object.connectionChanged {
                    observer.observe(event: event, monitorManager: object, notificationCenter: self)
                }
            }
        }
    }
    
    // MARK: Swift Concurrency
    
    func hasObserver(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) -> Bool {
        pthread_rwlock_rdlock(&lock)
        defer { pthread_rwlock_unlock(&lock) }
        
        return observers[event.rawValue]?.keys.contains(observer.configurator.id) ?? false
    }
    
    func addAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async {
        await observerManager.addObserver(observer, forEvent: event)
    }
    
    func removeAsync(_ observer: NWMonitoringObserverProtocol, forEvent event: Notification.Name) async {
        await observerManager.removeObserver(observer, forEvent: event)
    }
    
    func postAsync(event: Notification.Name, object: NWMonitoringManager) async {
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
