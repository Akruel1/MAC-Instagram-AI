import XCTest
import AppKit
@testable import AppUI
@testable import Core

final class DonationClipboardTests: XCTestCase {
    func testCopyWritesExactConfiguredAddresses() {
        for wallet in DonationConfig.wallets {
            XCTAssertTrue(DonationClipboard.copyAddress(wallet))
            let pasted = NSPasteboard.general.string(forType: .string)
            XCTAssertEqual(pasted, wallet.address)
            XCTAssertEqual(pasted, DonationConfig.wallet(id: wallet.id)?.address)
        }
    }

    func testCopyRejectsTamperedWallet() {
        let original = DonationConfig.wallet(id: "eth")!
        let tampered = DonationConfig.Wallet(
            id: original.id,
            name: original.name,
            network: original.network,
            networkWarning: original.networkWarning,
            address: "0xdeadbeef"
        )
        XCTAssertFalse(DonationClipboard.copyAddress(tampered))
    }
}
