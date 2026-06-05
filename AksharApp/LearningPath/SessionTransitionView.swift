import SwiftUI

// MARK: - AksharModule UI helpers
// Shared across LearningPathPreviewView, LearningPathHomeView, SessionSummaryView

extension AksharModule {

    /// Asset name for the module's teddy illustration
    var teddyImageName: String {
        switch self {
        case .phonics: return "phonics_teddy"
        case .writing: return "writer_teddy"
        case .reading: return "reader_teddy"
        }
    }

    var subtitle: String {
        switch self {
        case .phonics: return "Letter sounds & recognition"
        case .writing: return "Tracing & letter formation"
        case .reading: return "Stories & comprehension"
        }
    }

    var systemIcon: String {
        switch self {
        case .phonics: return "speaker.wave.2.fill"
        case .writing: return "pencil.tip"
        case .reading: return "book.fill"
        }
    }

    /// Short celebration message shown in the completion alert
    var completionMessage: String {
        switch self {
        case .phonics: return "Your ears are really sharp today!"
        case .writing: return "Beautiful letters — great tracing!"
        case .reading: return "Wonderful reading session!"
        }
    }

    var durationHint: String {
        switch self {
        case .phonics: return "~5 min"
        case .writing: return "~5 min"
        case .reading: return "~8 min"
        }
    }
}
