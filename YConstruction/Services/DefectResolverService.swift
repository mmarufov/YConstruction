import Foundation

struct ResolvedElement: Sendable {
    let element: ElementIndex.Element
    let confidence: Double
}

enum ResolverResult: Sendable {
    case match(ResolvedElement)
    case ambiguous([ResolvedElement])
    case notFound
}

struct ElementQuery: Sendable {
    var storey: String?
    var space: String?
    var elementType: String?
    var orientation: String?
}

final class DefectResolverService: @unchecked Sendable {
    private(set) var index: ElementIndex?
    private var byGuid: [String: ElementIndex.Element] = [:]

    init() {}

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ElementIndex.self, from: data)
        self.index = decoded
        self.byGuid = decoded.elements
    }

    func loadFromBundle(resource: String = "element_index", subdirectory: String = "DemoProject") throws {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url else {
            throw NSError(
                domain: "DefectResolver",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "element_index.json not found in bundle"]
            )
        }
        try load(from: url)
    }

    func element(by guid: String) -> ElementIndex.Element? {
        byGuid[guid]
    }

    func resolve(_ query: ElementQuery, ambiguityThreshold: Int = 4) -> ResolverResult {
        guard let elements = index?.elements.values, !elements.isEmpty else {
            return .notFound
        }

        let scored: [ResolvedElement] = elements.compactMap { el in
            let score = matchScore(el, query: query)
            guard score > 0 else { return nil }
            return ResolvedElement(element: el, confidence: score)
        }
        .sorted { $0.confidence > $1.confidence }

        guard let best = scored.first else { return .notFound }

        let topTier = scored.filter { $0.confidence == best.confidence }
        if topTier.count == 1 {
            return .match(best)
        }

        let candidates = Array(topTier.prefix(ambiguityThreshold))
        return .ambiguous(candidates)
    }

    private func matchScore(_ el: ElementIndex.Element, query: ElementQuery) -> Double {
        var score = 0.0
        var possible = 0.0

        if let q = query.storey {
            possible += 4
            if el.storey?.caseInsensitiveCompare(q) == .orderedSame { score += 4 }
        }
        if let q = query.space {
            possible += 3
            if el.space?.caseInsensitiveCompare(q) == .orderedSame { score += 3 }
        }
        if let q = query.elementType {
            possible += 2
            if el.elementType.caseInsensitiveCompare(q) == .orderedSame { score += 2 }
        }
        if let q = query.orientation {
            possible += 1
            if el.orientation?.caseInsensitiveCompare(q) == .orderedSame { score += 1 }
        }

        guard possible > 0 else { return 0 }
        return score / possible
    }
}
