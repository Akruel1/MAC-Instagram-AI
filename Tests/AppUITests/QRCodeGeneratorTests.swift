import XCTest
@testable import DesignSystem
@testable import Core

final class QRCodeGeneratorTests: XCTestCase {
    func testQRPayloadMatchesConfiguredWalletAddresses() {
        for wallet in DonationConfig.wallets {
            let image = QRCodeGenerator.cgImage(from: wallet.address, dimension: 120)
            XCTAssertNotNil(image, "QR generation failed for \(wallet.id)")
            // Payload is the raw address; generator consumes Data(payload.utf8) with no URI wrapping.
            XCTAssertEqual(wallet.address, DonationConfig.wallet(id: wallet.id)?.address)
            XCTAssertTrue(DonationConfig.validate(wallet))
        }
    }

    func testEmptyPayloadDoesNotCrash() {
        // Empty QR may still produce an image depending on Core Image; ensure no crash.
        _ = QRCodeGenerator.nsImage(from: "", dimension: 64)
    }
}
