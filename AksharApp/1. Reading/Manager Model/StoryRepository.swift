import Foundation

final class StoryRepository {

    private let stories: [Story]
    private let checkpointSets: [CheckpointSet]

    private let availableLevels: [String]

    init(bundleDataLoader: BundleDataLoader) {
        stories = bundleDataLoader.load("stories", as: StoriesResponse.self).stories
        checkpointSets = bundleDataLoader.load("checkpoints", as: CheckpointsResponse.self).checkpoints

        var seen  = Set<String>()
        availableLevels = stories.compactMap { story -> String? in seen.insert(story.difficulty).inserted ? story.difficulty : nil
        }
    }

    // MARK: - Story Queries
    func stories(for difficulty: String) -> [Story] {
        stories.filter { $0.difficulty == difficulty }
    }

    func story(by id: String) -> Story? {
        stories.first { $0.id == id }
    }

    func randomStory() -> Story? {
        stories.randomElement()
    }

    func nextStory(after storyId: String) -> Story? {
        guard let idx = stories.firstIndex(where: { $0.id == storyId }),
              idx < stories.count - 1 else { return nil }
        return stories[idx + 1]
    }

    func findStory(for storyId: String) -> Story? {
        for level in availableLevels {
            if let match = stories(for: level).first(where: { $0.id == storyId }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Checkpoint Queries
    func checkpointItem(storyId: String, pageNumber: Int) -> CheckpointItem? {
        checkpointSets.first(where: { $0.id == storyId })?
                      .content.first(where: { $0.pageNumber == pageNumber })
    }
    func getTotalCheckpoints(for story: Story) -> Int {
        return story.content.filter { $0.checkAfter }.count
    }
}
