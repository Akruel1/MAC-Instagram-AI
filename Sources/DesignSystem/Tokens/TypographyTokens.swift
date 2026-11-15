import SwiftUI

public enum StudioType {
    public static let display = Font.system(size: 28, weight: .semibold, design: .default)
    public static let title = Font.system(size: 20, weight: .semibold, design: .default)
    public static let headline = Font.system(size: 15, weight: .semibold, design: .default)
    public static let body = Font.system(size: 13, weight: .regular, design: .default)
    public static let callout = Font.system(size: 12, weight: .medium, design: .default)
    public static let caption = Font.system(size: 11, weight: .regular, design: .default)
    public static let metric = Font.system(size: 22, weight: .semibold, design: .default).monospacedDigit()
    public static let timecode = Font.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit()
    public static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
}
