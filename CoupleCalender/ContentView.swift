//
//  ContentView.swift
//  CoupleCalender
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import SwiftUI

struct ContentView: View {
    let sessionStore: AppSessionStore?
    let configurationError: SupabaseConfigurationError?

    var body: some View {
        Group {
            if let sessionStore {
                switch sessionStore.state {
                case .loading:
                    ProgressView("Yükleniyor…")
                case .signedOut:
                    AuthView(sessionStore: sessionStore)
                case .signedInNeedsProfile:
                    ProfileSetupView(sessionStore: sessionStore)
                case .signedInUnpaired:
                    PairingView(sessionStore: sessionStore)
                case let .signedInPaired(profile, partner, _):
                    CalendarRootView(sessionStore: sessionStore, profile: profile, partner: partner)
                case let .recoverableError(message):
                    RecoverableErrorView(message: message, sessionStore: sessionStore)
                }
            } else if let configurationError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    Text("Supabase yapılandırması gerekli")
                        .font(.headline)
                    Text(configurationError.localizedDescription)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .animation(.default, value: sessionStore?.state)
    }
}

private struct RecoverableErrorView: View {
    let message: String
    let sessionStore: AppSessionStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(message).multilineTextAlignment(.center)
            Button("Tekrar Dene") {
                Task { await sessionStore.retry() }
            }
            .buttonStyle(.borderedProminent)
            Button("Oturumu Kapat") {
                Task { await sessionStore.signOut() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    ContentView(sessionStore: nil, configurationError: nil)
}
