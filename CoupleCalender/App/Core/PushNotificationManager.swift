import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

extension Notification.Name {
    static let coupleCalenderAPNsToken = Notification.Name("CoupleCalender.apnsToken")
    static let coupleCalenderAPNsRegistrationFailed = Notification.Name("CoupleCalender.apnsRegistrationFailed")
    static let coupleCalenderNotificationResponse = Notification.Name("CoupleCalender.notificationResponse")
}

final class CoupleCalenderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var pendingNotificationNavigation: NotificationNavigationTarget?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .coupleCalenderAPNsToken, object: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(name: .coupleCalenderAPNsRegistrationFailed, object: error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let target = NotificationNavigationTarget(userInfo: userInfo) {
            pendingNotificationNavigation = target
        }
        NotificationCenter.default.post(
            name: .coupleCalenderNotificationResponse,
            object: response.notification.request.content.userInfo
        )
        completionHandler()
    }

    func consumePendingNotificationNavigation() -> NotificationNavigationTarget? {
        defer { pendingNotificationNavigation = nil }
        return pendingNotificationNavigation
    }
}

@MainActor
@Observable
final class PushNotificationManager {
    private let dataService: SupabaseDataService
    private let center = UNUserNotificationCenter.current()
    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false
    private var deviceToken: String?

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pendingNavigation: NotificationNavigationTarget?
    private(set) var navigationRevision = 0

    private let offerSeenKey = "notifications.permissionOfferSeen"

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    var shouldShowPermissionOffer: Bool {
        authorizationStatus == .notDetermined
            && !UserDefaults.standard.bool(forKey: offerSeenKey)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observers.append(NotificationCenter.default.addObserver(
            forName: .coupleCalenderAPNsToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? Data else { return }
            Task { @MainActor [weak self] in
                await self?.receiveDeviceToken(token)
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .coupleCalenderNotificationResponse,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.object as? [AnyHashable: Any],
                  let target = NotificationNavigationTarget(userInfo: userInfo)
            else { return }
            Task { @MainActor [weak self] in
                self?.pendingNavigation = target
                self?.navigationRevision += 1
            }
        })

        if let appDelegate = UIApplication.shared.delegate as? CoupleCalenderAppDelegate,
           let target = appDelegate.consumePendingNotificationNavigation() {
            pendingNavigation = target
            navigationRevision += 1
        }

        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            await persistDeviceTokenIfPossible()
        default:
            break
        }
    }

    func requestAuthorization() async {
        UserDefaults.standard.set(true, forKey: offerSeenKey)
        guard authorizationStatus == .notDetermined else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                await persistDeviceTokenIfPossible()
            }
        } catch {
            await refreshAuthorizationStatus()
        }
    }

    func dismissPermissionOffer() {
        UserDefaults.standard.set(true, forKey: offerSeenKey)
    }

    func syncDeviceTokenIfPossible() async {
        await persistDeviceTokenIfPossible()
    }

    func removeCurrentDeviceToken() async {
        guard let deviceToken else { return }
        self.deviceToken = nil
        try? await dataService.removeDeviceToken(token: deviceToken)
    }

    func clearPendingNavigation() {
        pendingNavigation = nil
        navigationRevision += 1
    }

    func consumePendingNavigation(validatingPartnerID partnerID: UUID) -> NotificationNavigationTarget? {
        guard let target = pendingNavigation else { return nil }
        pendingNavigation = nil

        guard target.calendarOwnerID == partnerID else { return nil }
        return target
    }

    private func receiveDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else { return }
        deviceToken = token
        await persistDeviceTokenIfPossible()
    }

    private func persistDeviceTokenIfPossible() async {
        guard let deviceToken, dataService.client.auth.currentSession != nil else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        _ = try? await dataService.registerDeviceToken(
            token: deviceToken,
            environment: environment,
            appVersion: version
        )
    }

}
