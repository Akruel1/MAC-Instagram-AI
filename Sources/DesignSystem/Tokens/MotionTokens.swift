import SwiftUI

public enum StudioMotion {
    public static let hover = Animation.easeOut(duration: 0.12)
    public static let state = Animation.easeInOut(duration: 0.20)
    public static let navigation = Animation.easeInOut(duration: 0.28)

    /// Prefer targeted opacity/offset. Avoid animating large view trees.
    public static func reduced(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    public static func withMotion(_ reduceMotion: Bool, _ animation: Animation, _ body: () -> Void) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        } else {
            withAnimation(animation, body)
        }
    }
}
