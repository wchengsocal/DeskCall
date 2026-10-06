import Foundation

struct CallerProfile: Codable, Identifiable, Hashable {
    var phoneNumber: String
    var name: String
    var title: String
    var company: String
    var linkedinURL: String
    var lineType: String
    var carrier: String
    var spamScore: Int
    var source: String
    var cached: Bool

    var id: String { phoneNumber }

    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case name
        case title
        case company
        case linkedinURL = "linkedin_url"
        case lineType = "line_type"
        case carrier
        case spamScore = "spam_score"
        case source
        case cached
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phoneNumber = try c.decode(String.self, forKey: .phoneNumber)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Caller"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        linkedinURL = try c.decodeIfPresent(String.self, forKey: .linkedinURL) ?? ""
        lineType = try c.decodeIfPresent(String.self, forKey: .lineType) ?? "unknown"
        carrier = try c.decodeIfPresent(String.self, forKey: .carrier) ?? ""
        spamScore = try c.decodeIfPresent(Int.self, forKey: .spamScore) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "none"
        cached = try c.decodeIfPresent(Bool.self, forKey: .cached) ?? false
    }

    init(
        phoneNumber: String,
        name: String = "Unknown Caller",
        title: String = "",
        company: String = "",
        linkedinURL: String = "",
        lineType: String = "unknown",
        carrier: String = "",
        spamScore: Int = 0,
        source: String = "none",
        cached: Bool = false
    ) {
        self.phoneNumber = phoneNumber
        self.name = name
        self.title = title
        self.company = company
        self.linkedinURL = linkedinURL
        self.lineType = lineType
        self.carrier = carrier
        self.spamScore = spamScore
        self.source = source
        self.cached = cached
    }

    var isIdentified: Bool { name != "Unknown Caller" && !name.isEmpty }
    var isLikelySpam: Bool { spamScore >= 60 }

    /// What the Call Directory extension shows on the lock screen while ringing.
    var callerIDLabel: String {
        if isLikelySpam { return "⚠︎ Likely Spam" }
        var label = name
        if !company.isEmpty, company != "N/A", company != name {
            label += " · \(company)"
        }
        return label
    }
}

/// Entry stored for the Call Directory extension to load at refresh time.
struct DirectoryEntry: Codable, Hashable {
    var number: Int64
    var label: String
}

struct RemoteDirectory: Codable {
    var version: String
    var blocked: [Int64]
    var identified: [RemoteIdentified]

    struct RemoteIdentified: Codable {
        var number: Int64
        var label: String
    }
}
