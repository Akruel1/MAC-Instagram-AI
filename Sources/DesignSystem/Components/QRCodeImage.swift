import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

public enum QRCodeGenerator {
    /// Generates a QR code locally from the exact payload string (raw wallet address).
    public static func cgImage(from payload: String, dimension: CGFloat = 180) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(scaled, from: scaled.extent)
    }

    public static func nsImage(from payload: String, dimension: CGFloat = 180) -> NSImage? {
        guard let cg = cgImage(from: payload, dimension: dimension) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: dimension, height: dimension))
    }
}

public struct QRCodeImage: View {
    public let payload: String
    public let dimension: CGFloat

    public init(payload: String, dimension: CGFloat = 148) {
        self.payload = payload
        self.dimension = dimension
    }

    public var body: some View {
        Group {
            if let image = QRCodeGenerator.nsImage(from: payload, dimension: dimension) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: dimension, height: dimension)
                    .accessibilityLabel("QR code for wallet address")
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                    .frame(width: dimension, height: dimension)
                    .overlay(
                        Text("QR unavailable")
                            .font(StudioType.caption)
                    )
            }
        }
    }
}
