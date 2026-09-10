import Foundation

enum AppErrorMessage {
    static func authentication(_ error: Error) -> String {
        let value = error.localizedDescription.lowercased()

        if value.contains("invalid login credentials") || value.contains("invalid password") {
            return "E-posta veya parola hatalı."
        }
        if value.contains("email not confirmed") || value.contains("email_not_confirmed") {
            return "E-posta adresini doğruladıktan sonra giriş yapabilirsin."
        }
        if value.contains("already registered") || value.contains("user already registered") {
            return "Bu e-posta adresi zaten kayıtlı. Giriş yapmayı deneyebilirsin."
        }
        if value.contains("password") && value.contains("weak") {
            return "Parolan en az 8 karakter olmalı."
        }
        return "Kimlik doğrulama sırasında bir sorun oluştu. Lütfen tekrar dene."
    }

    static func pairing(_ error: Error) -> String {
        let value = error.localizedDescription.lowercased()

        if value.contains("profile_required") {
            return "Önce profil adını tamamlamalısın."
        }
        if value.contains("invite_not_found") {
            return "Davet kodu bulunamadı."
        }
        if value.contains("invite_expired") {
            return "Bu davet kodunun süresi dolmuş."
        }
        if value.contains("invite_already_used") {
            return "Bu davet kodu daha önce kullanılmış."
        }
        if value.contains("cannot_join_self") {
            return "Kendi davet koduna katılamazsın."
        }
        if value.contains("already_paired") {
            return "Zaten aktif bir partner bağlantın var."
        }
        if value.contains("partner_unavailable") {
            return "Partner bağlantısı artık kullanılamıyor."
        }
        if value.contains("no_pending_invite") {
            return "İptal edilecek bekleyen davet yok."
        }
        if value.contains("no_active_couple") {
            return "Sonlandırılacak aktif bağlantı yok."
        }
        if value.contains("not_authenticated") {
            return "Oturumun sona ermiş. Lütfen tekrar giriş yap."
        }
        return "Bağlantı işlemi tamamlanamadı. Lütfen tekrar dene."
    }

    static func memory(_ error: Error) -> String {
        if let validationError = error as? MemoryContentValidationError {
            switch validationError {
            case .empty:
                return "Anı boş bırakılamaz."
            case .tooLong:
                return "Anı 10.000 karakteri geçemez."
            }
        }
        if let serviceError = error as? SupabaseDataServiceError,
           serviceError == .notAuthenticated {
            return "Oturumun sona ermiş. Lütfen tekrar giriş yap."
        }

        let value = error.localizedDescription.lowercased()
        if value.contains("duplicate key") || value.contains("memories_owner_id_calendar_day_key") {
            return "Bu gün için zaten bir anı bulunuyor."
        }
        if value.contains("permission denied") || value.contains("row-level security") {
            return "Bu anı üzerinde değişiklik yapma yetkin yok."
        }
        if value.contains("unauthorized") || value.contains("jwt") || value.contains("not authenticated") {
            return "Oturumun sona ermiş. Lütfen tekrar giriş yap."
        }
        return "Anı işlemi tamamlanamadı. Lütfen tekrar dene."
    }

    static func reaction(_ error: Error) -> String {
        if error is SupabaseDataServiceError {
            return "Oturumun sona ermiş olabilir. Lütfen tekrar giriş yap."
        }
        let value = error.localizedDescription.lowercased()
        if value.contains("permission") || value.contains("row-level security") || value.contains("42501") {
            return "Bu anıya tepki verme yetkin yok."
        }
        return "Tepki kaydedilemedi. Lütfen tekrar dene."
    }

    static func dayColor(_ error: Error) -> String {
        if error is SupabaseDataServiceError {
            return "Oturumun sona ermiş olabilir. Lütfen tekrar giriş yap."
        }
        let value = error.localizedDescription.lowercased()
        if value.contains("permission") || value.contains("row-level security") || value.contains("42501") {
            return "Bu güne renk verme yetkin yok."
        }
        return "Gün rengi kaydedilemedi. Lütfen tekrar dene."
    }
}
