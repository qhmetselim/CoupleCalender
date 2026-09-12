import SwiftUI

struct CalendarRootView: View {
    let sessionStore: AppSessionStore
    let coupleID: UUID
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarStore: CalendarStore

    init(sessionStore: AppSessionStore, profile: Profile, partner: Profile, coupleID: UUID) {
        self.sessionStore = sessionStore
        self.coupleID = coupleID
        _calendarStore = State(initialValue: CalendarStore(
            dataService: sessionStore.supabaseDataService,
            profile: profile,
            partner: partner,
            coupleID: coupleID
        ))
    }

    var body: some View {
        @Bindable var calendarStore = calendarStore

        NavigationStack {
            VStack(spacing: 12) {
                notificationPermissionOffer

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
        .task(id: coupleID) {
            await calendarStore.startRealtime(coupleID: coupleID)
            await calendarStore.refreshPartnerWidgetSnapshot()
        }
        .task(id: sessionStore.pushNotifications.navigationRevision) {
            await applyPendingNotificationNavigation()
        }
        .task(id: sessionStore.widgetNavigationRevision) {
            await applyPendingWidgetNavigation()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await calendarStore.startRealtime(coupleID: coupleID)
                await calendarStore.reloadCurrentPeriod()
                await calendarStore.refreshPartnerWidgetSnapshot()
            }
        }
        .onDisappear {
            Task { await calendarStore.stopRealtime() }
        }
        .refreshable {
            await calendarStore.reloadCurrentPeriod()
            await calendarStore.refreshPartnerWidgetSnapshot()
        }
    }

    @ViewBuilder
    private var notificationPermissionOffer: some View {
        if sessionStore.pushNotifications.shouldShowPermissionOffer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Partnerin yeni bir anı eklediğinde haber almak ister misin?", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Button("Bildirimleri Aç") {
                        Task { await sessionStore.pushNotifications.requestAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Şimdi Değil") {
                        sessionStore.pushNotifications.dismissPermissionOffer()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func applyPendingNotificationNavigation() async {
        guard let target = sessionStore.pushNotifications.consumePendingNavigation(
            validatingPartnerID: calendarStore.partner.id
        ) else { return }

        let previousKey = calendarStore.visiblePeriodKey
        calendarStore.openNotificationTarget(target)
        if previousKey == calendarStore.visiblePeriodKey {
            await calendarStore.reloadCurrentPeriod()
        }
    }

    private func applyPendingWidgetNavigation() async {
        guard let target = sessionStore.consumePendingWidgetDeepLink() else { return }

        let previousKey = calendarStore.visiblePeriodKey
        calendarStore.openWidgetTarget(target)
        if previousKey == calendarStore.visiblePeriodKey {
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
