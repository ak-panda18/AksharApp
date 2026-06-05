import Foundation

enum ExerciseType: CaseIterable {
    case rhyme, detective, quizMyStory, fluency, wordBuilder

    var coverImageName: String {
        switch self {
        case .rhyme: return "rhyme_cover"
        case .detective: return "detective_cover"
        case .quizMyStory: return "quiz_cover"
        case .fluency: return "fluency_cover"
        case .wordBuilder: return "wordbuilder_cover"
        }
    }

    var titleText: String {
        switch self {
        case .rhyme: return "Rhyme Words"
        case .detective: return "Sound Detective"
        case .quizMyStory: return "Quiz My Story"
        case .fluency: return "Fluency Drills"
        case .wordBuilder: return "Word Builder"
        }
    }

    var subtitleText: String {
        switch self {
        case .rhyme:
            return "Tap words that rhyme with the sound!"
        case .detective:
            return "Listen to the word and identify the first letter!"
        case .quizMyStory:
            return "Read the paragraph and answer the question!"
        case .fluency:
            return "See the words. \nTap the start button \nand say them!"
        case .wordBuilder:
            return "Look at the picture and build the word!"
        }
    }

    var storyboardID: String {
        switch self {
        case .rhyme: return "RhymeWordsVC"
        case .detective: return "SoundDetectorVC"
        case .quizMyStory: return "QuizMyStoryVC"
        case .fluency: return "FluencyDrillsVC"
        case .wordBuilder: return "WordBuilderVC"
        }
    }
    
    func cycleKey(uid: String) -> String {
        let base: String
        switch self {
        case .rhyme:        base = "rhyme_words_cycle"
        case .detective:    base = "sound_detector_cycle"
        case .quizMyStory:  base = "quiz_my_story_cycle"
        case .fluency:      base = "fluency_cycle"
        case .wordBuilder:  base = "word_builder_cycle"
        }
        return "\(base)_\(uid)"
    }

    var exerciseKey: String {
        switch self {
        case .rhyme: return "rhyme_words"
        case .detective: return "sound_detector"
        case .quizMyStory: return "quiz_my_story"
        case .fluency: return "fluency_drill"
        case .wordBuilder: return "word_builder"
        }
    }
}
