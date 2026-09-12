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
                    AppLaunchLoadingView()
                case .signedOut:
                    AuthView(sessionStore: sessionStore)
                case .signedInNeedsProfile:
                    ProfileSetupView(sessionStore: sessionStore)
                case .signedInUnpaired:
                    PairingView(sessionStore: sessionStore)
                case let .signedInPaired(profile, partner, couple):
                    CalendarRootView(
                        sessionStore: sessionStore,
                        profile: profile,
                        partner: partner,
                        coupleID: couple.id
                    )
                case let .recoverableError(message):
                    RecoverableErrorView(message: message, sessionStore: sessionStore)
                }
            } else if let configurationError {
                AppConfigurationErrorView(error: configurationError)
            }
        }
        .animation(.default, value: sessionStore?.state)
        .tint(AppDesign.accent)
    }
}

private struct AppLaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppDesign.accent)
            ProgressView()
            Text("Takvimin hazırlanıyor…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.pageBackground.ignoresSafeArea())
    }
}

private struct AppConfigurationErrorView: View {
    let error: SupabaseConfigurationError

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Supabase yapılandırması gerekli")
                .font(.title2.weight(.bold))
            Text(error.localizedDescription)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, AppDesign.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(AppDesign.pageBackground.ignoresSafeArea())
    }
}

private struct RecoverableErrorView: View {
    let message: String
    let sessionStore: AppSessionStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(AppDesign.accent)
            Text(message).multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Tekrar Dene") {
                Task { await sessionStore.retry() }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            Button("Oturumu Kapat") {
                Task { await sessionStore.signOut() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 420)
        .padding()
        .background(AppDesign.pageBackground.ignoresSafeArea())
        .tint(AppDesign.accent)
    }
}

#Preview {
    ContentView(sessionStore: nil, configurationError: nil)
}
