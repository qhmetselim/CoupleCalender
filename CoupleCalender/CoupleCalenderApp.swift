//
//  CoupleCalenderApp.swift
//  CoupleCalender
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import SwiftUI

@main
struct CoupleCalenderApp: App {
    @UIApplicationDelegateAdaptor(CoupleCalenderAppDelegate.self) private var appDelegate
    private let dependencies: AppDependencies
    @State private var sessionStore: AppSessionStore?

    init() {
        let dependencies = AppDependencies()
        self.dependencies = dependencies
        _sessionStore = State(initialValue: dependencies.supabaseDataService.map {
            AppSessionStore(dataService: $0)
        })
    }

    var body: some Scene {
        WindowGroup {
            if let sessionStore {
                ContentView(sessionStore: sessionStore, configurationError: dependencies.configurationError)
                    .task { sessionStore.start() }
            } else {
                ContentView(sessionStore: nil, configurationError: dependencies.configurationError)
            }
        }
    }
}
