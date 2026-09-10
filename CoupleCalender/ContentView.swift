//
//  ContentView.swift
//  CoupleCalender
//
//  Created by Ahmet Selim Arslantürk on 10.09.2026.
//

import SwiftUI

struct ContentView: View {
    let configurationError: SupabaseConfigurationError?

    var body: some View {
        VStack {
            Image(systemName: configurationError == nil ? "checkmark.seal" : "exclamationmark.triangle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(configurationError == nil ? "CoupleCalender foundation hazır" : "Supabase yapılandırması gerekli")
                .font(.headline)
            if let configurationError {
                Text(configurationError.localizedDescription)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView(configurationError: nil)
}
