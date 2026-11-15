import Foundation

/// Immutable donation destinations. Never fetched remotely. Never mutable by AI/MCP tools.
public enum DonationConfig: Sendable {
    public struct Wallet: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let network: String
        public let networkWarning: String
        public let address: String

        public init(id: String, name: String, network: String, networkWarning: String, address: String) {
            self.id = id
            self.name = name
            self.network = network
            self.networkWarning = networkWarning
            self.address = address
        }
    }

    public static let wallets: [Wallet] = [
        Wallet(
            id: "usdt-trc20",
            name: "USDT",
            network: "TRC20 (TRON network)",
            networkWarning: "TRC20 / TRON only. Sending on another network may permanently lose funds.",
            address: "TFDgn37KdCdLNodVsznUrivpxNS24SBb7t"
        ),
        Wallet(
            id: "ltc",
            name: "Litecoin",
            network: "LTC",
            networkWarning: "Send Litecoin (LTC) only to this address.",
            address: "ltc1qh5h8xv7dy2z4mny2g5amyjnw0qddypgfxsjs6j"
        ),
        Wallet(
            id: "btc",
            name: "Bitcoin",
            network: "BTC",
            networkWarning: "Send Bitcoin (BTC) only to this address.",
            address: "bc1qmjlgq983f3c6q08gs7lgap2sl6vl544vyty9aa"
        ),
        Wallet(
            id: "eth",
            name: "Ethereum",
            network: "Ethereum Mainnet",
            networkWarning: "Ethereum Mainnet only. Do not use other L2 or alternate chains.",
            address: "0xbe417ec282Cda431D3c76DC8B75673c5BC6a0d49"
        )
    ]

    public static func wallet(id: String) -> Wallet? {
        wallets.first { $0.id == id }
    }

    public static func validate(_ wallet: Wallet) -> Bool {
        wallets.contains(where: { $0.id == wallet.id && $0.address == wallet.address })
    }
}
