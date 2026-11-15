import AppKit
import Core

enum DonationClipboard {
    /// Copies the exact configured wallet address. Returns false if validation fails.
    /// Does not log clipboard contents.
    @discardableResult
    static func copyAddress(_ wallet: DonationConfig.Wallet) -> Bool {
        guard DonationConfig.validate(wallet) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wallet.address, forType: .string)
        return true
    }
}
