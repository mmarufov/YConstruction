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

struct PositionResolution: Sendable, Equatable {
    enum Tier: String, Sendable { case element, spaceCenter, storeyCenter, projectCenter }
    let centroid: SIMD3<Double>
    let bboxMin: SIMD3<Double>
    let bboxMax: SIMD3<Double>
    let tier: Tier
    let matchedGuid: String?
}

nonisolated final class DefectResolverService: @unchecked Sendable {
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

    // MARK: - IFC vocabulary

    var availableStoreys: [String] {
        guard let index else { return [] }
        return Array(Set(index.elements.values.compactMap { $0.storey })).sorted()
    }

    var availableSpaces: [String] {
        guard let index else { return [] }
        return Array(Set(index.elements.values.compactMap { $0.space })).sorted()
    }

    var availableElementTypes: [String] {
        guard let index else { return [] }
        return Array(Set(index.elements.values.map { $0.elementType })).sorted()
    }

    var availableOrientations: [String] {
        guard let index else { return [] }
        return Array(Set(index.elements.values.compactMap { $0.orientation })).sorted()
    }

    // MARK: - Position resolution (tiered fallback)

    func bestPosition(
        storey: String?,
        space: String?,
        elementType: String?,
        orientation: String?
    ) -> PositionResolution? {
        guard let index else { return nil }
        let all = Array(index.elements.values)
        guard !all.isEmpty else { return nil }

        // Tier 1: scored match on all provided fields.
        let query = ElementQuery(storey: storey, space: space, elementType: elementType, orientation: orientation)
        switch resolve(query) {
        case .match(let r):
            return Self.resolution(from: r.element, tier: .element)
        case .ambiguous(let candidates):
            if let first = candidates.first {
                return Self.resolution(from: first.element, tier: .element)
            }
        case .notFound:
            break
        }

        // Tier 2: narrow to the space — prefer the IfcSpace itself, else average of space contents.
        if let storey, let space {
            let spaceQuery = ElementQuery(storey: storey, space: space, elementType: "space", orientation: nil)
            if case .match(let r) = resolve(spaceQuery) {
                return Self.resolution(from: r.element, tier: .spaceCenter)
            }
            let inSpace = all.filter {
                Self.caseInsensitiveEqual($0.storey, storey) &&
                Self.caseInsensitiveEqual($0.space, space)
            }
            if !inSpace.isEmpty {
                return Self.averaged(inSpace, tier: .spaceCenter)
            }
        }

        // Tier 3: storey-wide centroid.
        if let storey {
            let onStorey = all.filter { Self.caseInsensitiveEqual($0.storey, storey) }
            if !onStorey.isEmpty {
                return Self.averaged(onStorey, tier: .storeyCenter)
            }
        }

        // Tier 4: project-wide centroid. Anything beats (0, 0, 0).
        return Self.averaged(all, tier: .projectCenter)
    }

    private static func resolution(from el: ElementIndex.Element, tier: PositionResolution.Tier) -> PositionResolution {
        PositionResolution(
            centroid: el.centroidPoint,
            bboxMin: el.bboxMin,
            bboxMax: el.bboxMax,
            tier: tier,
            matchedGuid: el.guid
        )
    }

    private static func averaged(_ elements: [ElementIndex.Element], tier: PositionResolution.Tier) -> PositionResolution {
        precondition(!elements.isEmpty)
        var centroidSum = SIMD3<Double>(0, 0, 0)
        var minP = elements[0].bboxMin
        var maxP = elements[0].bboxMax
        for el in elements {
            centroidSum += el.centroidPoint
            let m = el.bboxMin
            let x = el.bboxMax
            minP = SIMD3(Swift.min(minP.x, m.x), Swift.min(minP.y, m.y), Swift.min(minP.z, m.z))
            maxP = SIMD3(Swift.max(maxP.x, x.x), Swift.max(maxP.y, x.y), Swift.max(maxP.z, x.z))
        }
        return PositionResolution(
            centroid: centroidSum / Double(elements.count),
            bboxMin: minP,
            bboxMax: maxP,
            tier: tier,
            matchedGuid: nil
        )
    }

    private static func caseInsensitiveEqual(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
