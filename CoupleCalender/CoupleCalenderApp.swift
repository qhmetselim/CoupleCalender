//
//  CoupleCalenderApp.swift
//  CoupleCalender
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import SwiftUI

@main
struct CoupleCalenderApp: App {
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView(configurationError: dependencies.configurationError)
        }
    }
}
