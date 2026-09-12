import SwiftUI

struct CalendarRootView: View {
    let sessionStore: AppSessionStore
    let coupleID: UUID
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarStore: CalendarStore
    @State private var reportRoute: ReportRoute?
    @State private var isShowingAccountSettings = false

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

                CalendarOwnerSwitcher(store: calendarStore)

                Picker("Görünüm", selection: $calendarStore.mode) {
                    ForEach(CalendarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(3)
                .background(AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityLabel("Takvim görünümü")

                CalendarNavigationHeader(store: calendarStore)

                CalendarModeContent(store: calendarStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            .navigationTitle(calendarStore.ownerName)
            .navigationBarTitleDisplayMode(.inline)
            .background(AppDesign.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    reportButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAccountSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Hesap ve bağlantı ayarları")
                }
            }
        }
        .sheet(item: $reportRoute) { route in
            ReportContainerView(
                route: route,
                dataService: sessionStore.supabaseDataService,
                calendar: calendarStore.engine.calendar
            )
        }
        .sheet(isPresented: $isShowingAccountSettings) {
            AccountSettingsView(
                sessionStore: sessionStore,
                profile: calendarStore.profile,
                partner: calendarStore.partner
            )
            .presentationDetents([.medium, .large])
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
    private var reportButton: some View {
        switch calendarStore.mode {
        case .month:
            if ReportPeriodEligibility.isCompleted(
                month: calendarStore.selectedDate.month,
                year: calendarStore.selectedDate.year,
                today: calendarStore.engine.today()
            ) {
                Button("Aylık Rapor") {
                    reportRoute = ReportRoute(kind: .monthly(
                        year: calendarStore.selectedDate.year,
                        month: calendarStore.selectedDate.month
                    ))
                }
            }
        case .year:
            if ReportPeriodEligibility.isCompleted(
                year: calendarStore.selectedDate.year,
                today: calendarStore.engine.today()
            ) {
                Button("Yıllık Rapor") {
                    reportRoute = ReportRoute(kind: .yearly(year: calendarStore.selectedDate.year))
                }
            }
        case .day, .week:
            EmptyView()
        }
    }

    @ViewBuilder
    private var notificationPermissionOffer: some View {
        if sessionStore.pushNotifications.shouldShowPermissionOffer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(AppDesign.accent)
                    Text("Partnerin yeni bir anı eklediğinde haber almak ister misin?")
                        .font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 10) {
                    Button("Bildirimleri Aç") {
                        Task { await sessionStore.pushNotifications.requestAuthorization() }
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button("Şimdi Değil") {
                        sessionStore.pushNotifications.dismissPermissionOffer()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous)
                    .strokeBorder(AppDesign.accent.opacity(0.16), lineWidth: 0.5)
            }
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

private struct CalendarOwnerSwitcher: View {
    let store: CalendarStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CalendarOwner.allCases) { owner in
                Button {
                    guard store.owner != owner else { return }
                    store.owner = owner
                    AppHaptics.selection()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: owner == .me ? "person.fill" : "person.2.fill")
                            .font(.caption.weight(.semibold))
                        Text(name(for: owner))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(store.owner == owner ? .white : .primary)
                    .background(store.owner == owner ? AppDesign.accent : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(owner == .me ? "Benim takvimim" : "\(store.partner.displayName ?? "Partnerimin") takvimi")
                .accessibilityAddTraits(store.owner == owner ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func name(for owner: CalendarOwner) -> String {
        switch owner {
        case .me: store.profile.displayName ?? "Ben"
        case .partner: store.partner.displayName ?? "Partnerim"
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
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Önceki dönem")

            VStack(spacing: 2) {
                Text(store.periodTitle())
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(store.mode.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button("Bugün") {
                store.moveToToday()
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(AppDesign.accent.opacity(0.10), in: Capsule())

            Button {
                store.moveToNextPeriod()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
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
