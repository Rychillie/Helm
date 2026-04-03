import SwiftUI

enum HelmTheme {
    enum Layout {
        static let screenSpacing: CGFloat = 20
        static let cardSpacing: CGFloat = 14
        static let sectionSpacing: CGFloat = 18
        static let cardPadding: CGFloat = 20
        static let composerPadding: CGFloat = 14
        static let bubblePadding: CGFloat = 14
        static let maxTranscriptWidth: CGFloat = 760
    }

    enum CornerRadius {
        static let card: CGFloat = 24
        static let composer: CGFloat = 22
        static let bubble: CGFloat = 22
        static let badge: CGFloat = 14
    }

    enum Motion {
        static let standard = Animation.spring(duration: 0.35, bounce: 0.15)
        static let subtle = Animation.easeInOut(duration: 0.2)
    }
}
