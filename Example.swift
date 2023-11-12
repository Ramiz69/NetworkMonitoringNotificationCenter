//
//  Example.swift
//  Eargasm
//
//  Created by Рамиз Кичибеков on 12.11.2023.
//  Copyright © 2023 Рамиз Кичибеков. All rights reserved.
//

import Foundation

final class ExampleClass {
    
    var identifier: AnyHashable {
        var hasher = Hasher()
        hasher.combine("The wolves go to hell")
        
        return hasher.finalize()
    }
    private let isAsyncCall = true
    private let networkMonitoringNotificationCenter: NWMonitoringNotificationCenterProtocol = NWMonitoringNotificationCenter.shared
    
    init() {
        if isAsyncCall {
            Task {
                await networkMonitoringNotificationCenter.addAsync(self, forEvent: .connectivityStatus)
            }
        } else {
            networkMonitoringNotificationCenter.add(self, forEvent: .connectivityStatus)
        }
        
    }
    
}

extension ExampleClass: NWMonitoringObserverProtocol {
    
    func observe(event: Notification.Name, 
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter) {
        print(monitorManager.currentConnectionType)
        print(monitorManager.isConnected)
        print(monitorManager.isExpensive)
    }
    
    func observe(event: Notification.Name,
                 monitorManager: NWMonitoringManagerProtocol,
                 notificationCenter: NWMonitoringNotificationCenter) async {
        print(monitorManager.currentConnectionType)
        print(monitorManager.isConnected)
        print(monitorManager.isExpensive)
    }
    
}
