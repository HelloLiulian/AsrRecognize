import Foundation

struct MeetingSummary: Codable, Hashable {
    var overview: String
    var keyPoints: [String]
    var actionItems: [ActionItem]
    var decisions: [String]

    init(
        overview: String,
        keyPoints: [String] = [],
        actionItems: [ActionItem] = [],
        decisions: [String] = []
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.decisions = decisions
    }

    enum CodingKeys: String, CodingKey {
        case overview, keyPoints, actionItems, decisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
    }

    var isEmpty: Bool {
        overview.isEmpty && keyPoints.isEmpty && actionItems.isEmpty && decisions.isEmpty
    }
}

struct ActionItem: Codable, Hashable {
    var task: String
    var owner: String?
    var deadline: String?

    init(task: String, owner: String? = nil, deadline: String? = nil) {
        self.task = task
        self.owner = owner
        self.deadline = deadline
    }

    enum CodingKeys: String, CodingKey {
        case task, owner, deadline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decodeIfPresent(String.self, forKey: .task) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        deadline = try container.decodeIfPresent(String.self, forKey: .deadline)
    }
}
