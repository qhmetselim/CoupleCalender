import SwiftUI

enum ReportRouteKind: Hashable, Sendable {
    case monthly(year: Int, month: Int)
    case yearly(year: Int)
}

struct ReportRoute: Identifiable, Hashable, Sendable {
    let kind: ReportRouteKind

    var id: String {
        switch kind {
        case let .monthly(year, month): "monthly-\(year)-\(month)"
        case let .yearly(year): "yearly-\(year)"
        }
    }
}

struct ReportContainerView: View {
    let route: ReportRoute
    let dataService: SupabaseDataService
    let calendar: Calendar

    @State private var monthlyReport: MonthlyReport?
    @State private var yearlyReport: YearlyReport?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var unavailableMessage: String?

    init(route: ReportRoute, dataService: SupabaseDataService, calendar: Calendar = .autoupdatingCurrent) {
        self.route = route
        self.dataService = dataService
        self.calendar = calendar
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Rapor hazırlanıyor…")
                } else if let unavailableMessage {
                    ContentUnavailableView(
                        "Rapor henüz hazır değil",
                        systemImage: "chart.bar.xaxis",
                        description: Text(unavailableMessage)
                    )
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Rapor yüklenemedi",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    reportContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: route.id) {
            await loadReport()
        }
    }

    @ViewBuilder
    private var reportContent: some View {
        switch route.kind {
        case .monthly:
            if let monthlyReport, let metrics = monthlyReport.metricsV1 {
                MonthlyReportView(report: monthlyReport, metrics: metrics, calendar: calendar)
            } else {
                reportDecodeError
            }
        case .yearly:
            if let yearlyReport, let metrics = yearlyReport.metricsV1 {
                YearlyReportView(report: yearlyReport, metrics: metrics, calendar: calendar)
            } else {
                reportDecodeError
            }
        }
    }

    private var reportDecodeError: some View {
        ContentUnavailableView(
            "Rapor biçimi desteklenmiyor",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Bu rapor sürümü bu uygulama tarafından okunamıyor.")
        )
    }

    private var navigationTitle: String {
        switch route.kind {
        case let .monthly(year, month): "\(monthName(month)) \(year)"
        case let .yearly(year): "\(year) Yıllık Rapor"
        }
    }

    private func loadReport() async {
        isLoading = true
        errorMessage = nil
        unavailableMessage = nil
        let today = CalendarDay(date: Date(), calendar: calendar)

        do {
            switch route.kind {
            case let .monthly(year, month):
                guard ReportPeriodEligibility.isCompleted(month: month, year: year, today: today) else {
                    unavailableMessage = year == today.year && month == today.month
                        ? "Bu ayın raporu ay tamamlandıktan sonra hazır olacak."
                        : "Gelecek aylar için rapor henüz oluşturulamaz."
                    isLoading = false
                    return
                }
                monthlyReport = try await dataService.ensureMonthlyReport(year: year, month: month)
            case let .yearly(year):
                guard ReportPeriodEligibility.isCompleted(year: year, today: today) else {
                    unavailableMessage = year == today.year
                        ? "Yıllık rapor yıl tamamlandıktan sonra hazır olacak."
                        : "Gelecek yıllar için rapor henüz oluşturulamaz."
                    isLoading = false
                    return
                }
                yearlyReport = try await dataService.ensureYearlyReport(year: year)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Rapor yüklenemedi. Lütfen tekrar dene."
        }

        isLoading = false
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(.dateTime.month(.wide))
    }
}

private struct MonthlyReportView: View {
    let report: MonthlyReport
    let metrics: MonthlyReportMetricsV1
    let calendar: Calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                reportHeader
                summary
                reactionSection
                colorSection
                activitySection

                if metrics.memoryCount == 0 {
                    Text("Bu ay henüz kayıtlı bir anı yoktu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aylık Rapor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(monthTitle)
                .font(.title2.weight(.bold))
            Text("Takvimindeki gerçek kayıt ve etkileşim istatistikleri")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ReportMetricCard(title: "Anı", value: "\(metrics.memoryCount)", systemImage: "note.text")
            ReportMetricCard(title: "Tepki", value: "\(metrics.reactionCount)", systemImage: "face.smiling")
            ReportMetricCard(title: "Tepki Oranı", value: percent(metrics.reactionCoverage), systemImage: "chart.bar")
            ReportMetricCard(title: "Anı Günü", value: "\(metrics.memoryDayCount)", systemImage: "calendar")
        }
    }

    @ViewBuilder
    private var reactionSection: some View {
        ReportSection(title: "Tepkiler", systemImage: "face.smiling") {
            if let top = metrics.mostUsedReaction {
                HStack(spacing: 12) {
                    Text(top.displayValue ?? top.reactionKey)
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("En çok kullanılan tepki")
                            .font(.subheadline.weight(.semibold))
                        Text("\(top.count) kez")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            distributionRows(metrics.reactionFrequency) { item in
                Text(item.displayValue ?? item.reactionKey)
                    .font(.title3)
                    .accessibilityLabel(item.reactionKey)
            } count: { item in item.count }
        }
    }

    @ViewBuilder
    private var colorSection: some View {
        ReportSection(title: "Gün renkleri", systemImage: "paintpalette") {
            if let top = metrics.mostUsedColor {
                HStack(spacing: 12) {
                    Circle()
                        .fill(DayColorPalette.color(for: top.colorKey))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.quaternary))
                    VStack(alignment: .leading) {
                        Text("En sık kullanılan gün rengi")
                            .font(.subheadline.weight(.semibold))
                        Text("\(top.count) gün")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(metrics.dayColorFrequency) { item in
                HStack {
                    Circle()
                        .fill(DayColorPalette.color(for: item.colorKey))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.quaternary))
                    Text(DayColorPalette.label(for: item.colorKey))
                    Spacer()
                    Text("\(item.count)")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        ReportSection(title: "Aktivite", systemImage: "calendar.badge.clock") {
            if let activeWeek = metrics.activeWeek {
                VStack(alignment: .leading, spacing: 4) {
                    Text("En aktif hafta")
                        .font(.subheadline.weight(.semibold))
                    Text("\(activeWeek.weekStart.rawValue) – \(activeWeek.weekEnd.rawValue)")
                    Text("\(activeWeek.memoryCount) anı")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Bu ay için en aktif hafta oluşmadı.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthTitle: String {
        var components = DateComponents(year: report.year, month: report.month, day: 1)
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func distributionRows<T: Identifiable, Row: View>(
        _ items: [T],
        @ViewBuilder label: @escaping (T) -> Row,
        count: @escaping (T) -> Int
    ) -> some View {
        ForEach(items) { item in
            HStack {
                label(item)
                Spacer()
                Text("\(count(item))")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct YearlyReportView: View {
    let report: YearlyReport
    let metrics: YearlyReportMetricsV1
    let calendar: Calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yıllık Rapor")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(report.year)")
                        .font(.title.weight(.bold))
                    Text("Takvimindeki gerçek kayıt ve etkileşim istatistikleri")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ReportMetricCard(title: "Toplam Anı", value: "\(metrics.memoryCount)", systemImage: "note.text")
                    ReportMetricCard(title: "Toplam Tepki", value: "\(metrics.reactionCount)", systemImage: "face.smiling")
                    ReportMetricCard(title: "Tepki Oranı", value: percent(metrics.reactionCoverage), systemImage: "chart.bar")
                    ReportMetricCard(title: "En Aktif Ay", value: activeMonthTitle, systemImage: "calendar")
                }

                ReportSection(title: "Aylık aktivite", systemImage: "chart.bar.xaxis") {
                    let maximum = max(1, metrics.monthlyBreakdown.map(\.memoryCount).max() ?? 1)
                    ForEach(metrics.monthlyBreakdown) { item in
                        HStack(spacing: 8) {
                            Text(monthName(item.month))
                                .frame(width: 78, alignment: .leading)
                                .font(.subheadline)
                            ProgressView(value: Double(item.memoryCount), total: Double(maximum))
                            Text("\(item.memoryCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ReportSection(title: "Tepkiler", systemImage: "face.smiling") {
                    if let top = metrics.mostUsedReaction {
                        Text("En çok kullanılan tepki: \(top.displayValue ?? top.reactionKey) · \(top.count) kez")
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(metrics.reactionFrequency) { item in
                        HStack {
                            Text(item.displayValue ?? item.reactionKey)
                                .font(.title3)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ReportSection(title: "Gün renkleri", systemImage: "paintpalette") {
                    if let top = metrics.mostUsedColor {
                        Text("En sık kullanılan gün rengi: \(DayColorPalette.label(for: top.colorKey)) · \(top.count) gün")
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(metrics.dayColorFrequency) { item in
                        HStack {
                            Circle()
                                .fill(DayColorPalette.color(for: item.colorKey))
                                .frame(width: 18, height: 18)
                            Text(DayColorPalette.label(for: item.colorKey))
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if metrics.memoryCount == 0 {
                    Text("Bu yıl henüz kayıtlı bir anı yoktu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var activeMonthTitle: String {
        guard let month = metrics.mostActiveMonth else { return "—" }
        return monthName(month)
    }

    private func monthName(_ month: Int) -> String {
        let date = calendar.date(from: DateComponents(year: report.year, month: month, day: 1)) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated))
    }
}

private struct ReportMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReportSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}
