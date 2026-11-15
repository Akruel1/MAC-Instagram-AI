import XCTest
@testable import Core

final class DonationConfigTests: XCTestCase {
    func testExactConfiguredWalletAddresses() {
        let expected: [(String, String)] = [
            ("usdt-trc20", "TFDgn37KdCdLNodVsznUrivpxNS24SBb7t"),
            ("ltc", "ltc1qh5h8xv7dy2z4mny2g5amyjnw0qddypgfxsjs6j"),
            ("btc", "bc1qmjlgq983f3c6q08gs7lgap2sl6vl544vyty9aa"),
            ("eth", "0xbe417ec282Cda431D3c76DC8B75673c5BC6a0d49")
        ]
        XCTAssertEqual(DonationConfig.wallets.count, expected.count)
        for (id, address) in expected {
            let wallet = DonationConfig.wallet(id: id)
            XCTAssertEqual(wallet?.address, address)
            XCTAssertTrue(DonationConfig.validate(wallet!))
        }
    }

    func testNetworkWarningsAreExplicit() {
        let usdt = DonationConfig.wallet(id: "usdt-trc20")!
        XCTAssertTrue(usdt.network.contains("TRC20"))
        XCTAssertTrue(usdt.networkWarning.contains("TRC20 / TRON only"))

        let eth = DonationConfig.wallet(id: "eth")!
        XCTAssertTrue(eth.network.contains("Ethereum Mainnet"))
        XCTAssertTrue(eth.networkWarning.contains("Ethereum Mainnet only"))
    }

    func testValidateRejectsTamperedAddress() {
        let original = DonationConfig.wallet(id: "btc")!
        let tampered = DonationConfig.Wallet(
            id: original.id,
            name: original.name,
            network: original.network,
            networkWarning: original.networkWarning,
            address: "not-the-real-address"
        )
        XCTAssertFalse(DonationConfig.validate(tampered))
    }
}
