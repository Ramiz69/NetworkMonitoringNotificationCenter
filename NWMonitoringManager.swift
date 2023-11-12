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

protocol NWMonitoringManagerProtocol: AnyObject, Sendable {
    var isConnected: Bool { get }
    var isExpensive: Bool { get }
    var currentConnectionType: NWInterface.InterfaceType? { get }
    var queue: DispatchQueue { get }
    
    func startMonitoring()
    func startMonitoringAsync() async
    func stopMonitoring()
}

final class NWMonitoringManager: NWMonitoringManagerProtocol {
    
    // MARK: - Properties
    
    static let shared = NWMonitoringManager()
    private let monitor: NWPathMonitor
    private(set) var isConnected = false
    private(set) var isExpensive = false
    private(set) var currentConnectionType: NWInterface.InterfaceType?
    let queue = DispatchQueue(label: "NetworkConnectivityMonitor",
                              qos: .background,
                              attributes: .concurrent,
                              autoreleaseFrequency: .workItem)
    private var pathStream: AsyncStream<NWPath>!
    private var continuation: AsyncStream<NWPath>.Continuation?
    
    // MARK: - Initial methods
    
    private init() {
        monitor = NWPathMonitor()
    }
    
    // MARK: - Public methods
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            
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
