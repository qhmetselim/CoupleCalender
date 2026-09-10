import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AppSessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedInNeedsProfile(userID: UUID)
        case signedInUnpaired(profile: Profile, pendingInviteExpiresAt: Date?)
        case signedInPaired(profile: Profile, partner: Profile, couple: Couple)
        case recoverableError(message: String)
    }

    private let dataService: SupabaseDataService
    private var authObservationTask: Task<Void, Never>?
    private var currentSession: Session?
    private var hasStarted = false

    private(set) var state: State = .loading
    private(set) var message: String?
    private(set) var messageIsError = false
    private(set) var latestInvite: PartnerInvite?

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    var supabaseDataService: SupabaseDataService { dataService }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let authStateChanges = dataService.client.auth.authStateChanges
        authObservationTask = Task { [weak self, authStateChanges] in
            for await (event, session) in authStateChanges {
                guard let self else { return }
                await self.handleAuthChange(event: event, session: session)
            }
        }
    }

    func signIn(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(normalizedEmail) else {
            showError("Geçerli bir e-posta adresi gir.")
            return
        }
        guard password.count >= 8 else {
            showError("Parolan en az 8 karakter olmalı.")
            return
        }

        state = .loading
        clearMessage()
        do {
            currentSession = try await dataService.client.auth.signIn(email: normalizedEmail, password: password)
            await reloadAuthenticatedState()
        } catch {
            state = .signedOut
            showError(AppErrorMessage.authentication(error))
        }
    }

    func signUp(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(normalizedEmail) else {
            showError("Geçerli bir e-posta adresi gir.")
            return
        }
        guard password.count >= 8 else {
            showError("Parolan en az 8 karakter olmalı.")
            return
        }

        state = .loading
        clearMessage()
        do {
            let response = try await dataService.client.auth.signUp(
                email: normalizedEmail,
                password: password
            )

            if let session = response.session {
                currentSession = session
                await reloadAuthenticatedState()
            } else {
                state = .signedOut
                showInfo("Kayıt tamamlandı. Giriş yapmadan önce e-posta adresini doğrula.")
            }
        } catch {
            state = .signedOut
            showError(AppErrorMessage.authentication(error))
        }
    }

    func signOut() async {
        do {
            try await dataService.client.auth.signOut()
        } catch {
            // The SDK clears its local session before the remote request. Keep the
            // local app state signed out even if the remote revoke request fails.
            state = .signedOut
            showError("Oturum kapatılamadı. Lütfen tekrar dene.")
        }
    }

    func saveProfile(displayName: String) async {
        guard let userID = currentSession?.user.id else {
            state = .signedOut
            return
        }

        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(normalizedName.count) else {
            showError("Görünen ad 1-80 karakter arasında olmalı.")
            return
        }

        state = .loading
        clearMessage()
        do {
            _ = try await dataService.saveProfile(userID: userID, displayName: normalizedName)
            await reloadAuthenticatedState()
        } catch {
            showError("Profil oluşturulamadı. Lütfen tekrar dene.")
            await reloadAuthenticatedState()
        }
    }

    func createOrRefreshInvite() async {
        do {
            latestInvite = try await dataService.createOrRefreshInvite()
            clearMessage()
            await reloadAuthenticatedState()
        } catch {
            showError(AppErrorMessage.pairing(error))
        }
    }

    func acceptInvite(code: String) async {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else {
            showError("Davet kodunu gir.")
            return
        }

        do {
            _ = try await dataService.acceptInvite(code: normalizedCode)
            latestInvite = nil
            clearMessage()
            await reloadAuthenticatedState()
        } catch {
            showError(AppErrorMessage.pairing(error))
        }
    }

    func cancelPendingInvite() async {
        do {
            try await dataService.cancelPendingInvite()
            latestInvite = nil
            clearMessage()
            await reloadAuthenticatedState()
        } catch {
            showError(AppErrorMessage.pairing(error))
        }
    }

    func retry() async {
        await reloadAuthenticatedState()
    }

    func clearMessage() {
        message = nil
        messageIsError = false
    }

    private func handleAuthChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .userUpdated:
            guard let session else {
                currentSession = nil
                state = .signedOut
                return
            }
            currentSession = session
            await reloadAuthenticatedState()
        case .signedOut, .userDeleted:
            currentSession = nil
            latestInvite = nil
            state = .signedOut
            clearMessage()
        case .tokenRefreshed, .passwordRecovery, .mfaChallengeVerified:
            if let session {
                currentSession = session
            }
        }
    }

    private func reloadAuthenticatedState() async {
        guard let session = currentSession ?? dataService.client.auth.currentSession else {
            state = .signedOut
            return
        }

        currentSession = session
        state = .loading

        do {
            guard let profile = try await dataService.fetchProfile(userID: session.user.id),
                  let displayName = profile.displayName,
                  !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                state = .signedInNeedsProfile(userID: session.user.id)
                return
            }

            let pairing = try await dataService.fetchPairingStatus()
            switch pairing.status {
            case "paired":
                guard let coupleID = pairing.coupleID, let partnerID = pairing.partnerID,
                      let partner = try await dataService.fetchProfile(userID: partnerID)
                else {
                    throw PairingStateError.partnerUnavailable
                }
                let couple = try await dataService.fetchCouple(id: coupleID)
                state = .signedInPaired(profile: profile, partner: partner, couple: couple)
            case "pending", "unpaired":
                state = .signedInUnpaired(
                    profile: profile,
                    pendingInviteExpiresAt: pairing.pendingInviteExpiresAt
                )
            default:
                throw PairingStateError.invalidStatus
            }
            clearMessage()
        } catch {
            state = .recoverableError(message: "Uygulama durumu yüklenemedi. Lütfen tekrar dene.")
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && !value.contains(" ")
    }

    private func showError(_ text: String) {
        message = text
        messageIsError = true
    }

    private func showInfo(_ text: String) {
        message = text
        messageIsError = false
    }
}

private enum PairingStateError: Error {
    case invalidStatus
    case partnerUnavailable
}
