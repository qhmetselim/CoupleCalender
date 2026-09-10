import SwiftUI

struct CalendarRootView: View {
    let sessionStore: AppSessionStore
    @State private var calendarStore: CalendarStore

    init(sessionStore: AppSessionStore, profile: Profile, partner: Profile) {
        self.sessionStore = sessionStore
        _calendarStore = State(initialValue: CalendarStore(
            dataService: sessionStore.supabaseDataService,
            profile: profile,
            partner: partner
        ))
    }

    var body: some View {
        @Bindable var calendarStore = calendarStore

        NavigationStack {
            VStack(spacing: 12) {
                Picker("Takvim sahibi", selection: $calendarStore.owner) {
                    ForEach(CalendarOwner.allCases) { owner in
                        Text(owner.title).tag(owner)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Görünüm", selection: $calendarStore.mode) {
                    ForEach(CalendarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                CalendarNavigationHeader(store: calendarStore)

                CalendarModeContent(store: calendarStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            .navigationTitle(calendarStore.ownerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Bağlantı") {
                            Label(calendarStore.profile.displayName ?? "Benim", systemImage: "person")
                            Label(calendarStore.partner.displayName ?? "Partnerim", systemImage: "person.2")
                        }
                        Button("Oturumu Kapat", role: .destructive) {
                            Task { await sessionStore.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Hesap seçenekleri")
                }
            }
        }
        .task(id: calendarStore.visiblePeriodKey) {
            await calendarStore.loadVisiblePeriod()
        }
        .refreshable {
            await calendarStore.reloadCurrentPeriod()
        }
    }
}

private struct CalendarNavigationHeader: View {
    let store: CalendarStore

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.moveToPreviousPeriod()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Önceki dönem")

            VStack(spacing: 2) {
                Text(store.periodTitle())
                    .font(.headline)
                    .lineLimit(1)
                Text(store.mode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button("Bugün") {
                store.moveToToday()
            }
            .font(.subheadline.weight(.semibold))

            Button {
                store.moveToNextPeriod()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Sonraki dönem")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}

private struct CalendarModeContent: View {
    let store: CalendarStore

    var body: some View {
        Group {
            switch store.mode {
            case .day:
                DayCalendarView(store: store)
            case .week:
                WeekCalendarView(store: store)
            case .month:
                MonthCalendarView(store: store)
            case .year:
                YearCalendarView(store: store)
            }
        }
        .overlay(alignment: .top) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .overlay {
            if let errorMessage = store.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("Tekrar Dene") {
                        Task { await store.reloadCurrentPeriod() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
