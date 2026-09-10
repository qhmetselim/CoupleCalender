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
}
