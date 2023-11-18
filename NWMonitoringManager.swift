//
//  NWMonitoringManager.swift
//  Eargasm
//
//  Created by Рамиз Кичибеков on 12.11.2023.
//  Copyright © 2023 Рамиз Кичибеков. All rights reserved.
//

import Foundation
import Network
import Dispatch
import Darwin

final class NWMonitoringManager: Sendable {
    
    // MARK: - Properties
    
    static let shared = NWMonitoringManager()
    private let monitor: NWPathMonitor
    private var _connectionChanged = false
    private(set) var connectionChanged: Bool {
        get {
            pthread_rwlock_rdlock(&lock)
            defer { pthread_rwlock_unlock(&lock) }
            
            return _connectionChanged
        } set {
            pthread_rwlock_wrlock(&lock)
            defer { pthread_rwlock_unlock(&lock) }
            
            _connectionChanged = newValue
        }
    }
    private(set) var isConnected = false
    private(set) var isExpensive = false
    private(set) var currentConnectionType: NWInterface.InterfaceType?
    private let queue = DispatchQueue(label: "NetworkConnectivityMonitor",
                                      qos: .background,
                                      attributes: .concurrent,
                                      autoreleaseFrequency: .workItem)
    private var pathStream: AsyncStream<NWPath>!
    private var continuation: AsyncStream<NWPath>.Continuation?
    private var previousPath: NWPath?
    private var lock = pthread_rwlock_t()
    
    // MARK: - Initial methods
    
    private init() {
        pthread_rwlock_init(&lock, nil)
        monitor = NWPathMonitor()
    }
    
    // MARK: - Public methods
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            
            defer {
                self.previousPath = path
            }
            if self.previousPath != path {
                self.connectionChanged = self.previousPath?.status != path.status
            } else {
                self.connectionChanged = false
            }
            if self.previousPath == nil {
                self.connectionChanged = true
            }
            self.isConnected = path.status != .unsatisfied
            self.isExpensive = path.isExpensive
            self.currentConnectionType = NWInterface.InterfaceType.allCases.filter { path.usesInterfaceType($0) }.first
            NWMonitoringNotificationCenter.shared.post(event: .connectivityStatus, object: self)
        }
        monitor.start(queue: queue)
    }
    
    func startMonitoringAsync() async {
        pathStream = stream()
        for await path in pathStream {
            defer {
                previousPath = path
            }
            if previousPath != path {
                connectionChanged = previousPath?.status != path.status
            } else {
                connectionChanged = false
            }
            if previousPath == nil {
                connectionChanged = true
            }
            isConnected = path.status != .unsatisfied
            isExpensive = path.isExpensive
            currentConnectionType = NWInterface.InterfaceType.allCases.filter { path.usesInterfaceType($0) }.first
            await NWMonitoringNotificationCenter.shared.postAsync(event: .connectivityStatus, object: self)
        }
    }
    
    func stopMonitoring() {
        if continuation != nil {
            continuation?.finish()
            continuation = nil
        }
        previousPath = nil
        connectionChanged = false
        monitor.cancel()
    }
    
    // MARK: - Private methods
    
    private func stream() -> AsyncStream<NWPath> {
        monitor.start(queue: queue)
        return AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            self?.monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
        }
    }
    
}

extension NWInterface.InterfaceType: CaseIterable {
    public static var allCases: [NWInterface.InterfaceType] = [
        .other,
        .wifi,
        .cellular,
        .loopback,
        .wiredEthernet
    ]
}

extension Notification.Name {
    static let connectivityStatus = Notification.Name(rawValue: "connectivityStatusChanged")
}
