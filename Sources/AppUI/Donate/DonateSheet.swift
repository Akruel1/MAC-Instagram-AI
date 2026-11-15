import SwiftUI
import DesignSystem
import Core

struct DonateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studioPalette) private var palette
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support the project")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("If you enjoy Instagram AI Studio, you can support its development.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Text("Verify the network before sending. Donations are optional and are never required to use the app.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(DonationConfig.wallets) { wallet in
                        walletCard(wallet)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 560, height: 640)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }

    private func walletCard(_ wallet: DonationConfig.Wallet) -> some View {
        let valid = DonationConfig.validate(wallet)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(wallet.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(wallet.network)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.accent)
                Spacer()
            }

            Text(wallet.networkWarning)
                .font(.system(size: 11))
                .foregroundStyle(palette.warning)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 14) {
                QRCodeImage(payload: wallet.address, dimension: 132)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("QR code for \(wallet.name) address")

                VStack(alignment: .leading, spacing: 8) {
                    Text(wallet.address)
                        .font(StudioType.mono)
                        .foregroundStyle(palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        StudioToolbarButton(
                            copiedID == wallet.id ? "Copied" : "Copy address",
                            systemImage: copiedID == wallet.id ? "checkmark" : "doc.on.doc",
                            isEnabled: valid
                        ) {
                            copy(wallet)
                        }
                        if !valid {
                            Text("Address mismatch")
                                .font(StudioType.caption)
                                .foregroundStyle(palette.danger)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.bgBase.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        )
    }

    private func copy(_ wallet: DonationConfig.Wallet) {
        guard DonationClipboard.copyAddress(wallet) else { return }
        copiedID = wallet.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedID == wallet.id { copiedID = nil }
        }
    }
}
