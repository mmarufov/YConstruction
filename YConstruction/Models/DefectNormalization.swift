import Foundation

enum DefectNormalization {
    static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedElementType(_ value: String?) -> String? {
        guard let normalized = normalizedValue(value) else { return nil }
        return normalized.lowercased() == "unknown" ? "surface" : normalized
    }

    static func normalizedDefectType(_ value: String?) -> String? {
        guard let normalized = normalizedValue(value) else { return nil }
        return normalized.lowercased() == "unknown" ? "field note" : normalized
    }

    static func normalizedSeverity(_ value: String?) -> Severity? {
        guard let normalized = normalizedValue(value)?.lowercased() else { return nil }
        switch normalized {
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        case "critical": return .critical
        case "unknown": return .medium
        default: return nil
        }
    }
}

extension Defect {
    func normalizedForUpload() -> Defect {
        var copy = self
        copy.guid = DefectNormalization.normalizedValue(guid) ?? guid
        copy.storey = DefectNormalization.normalizedValue(storey) ?? "Unknown"
        copy.space = DefectNormalization.normalizedValue(space)
        copy.elementType = DefectNormalization.normalizedElementType(elementType) ?? "surface"
        copy.orientation = DefectNormalization.normalizedValue(orientation)
        copy.defectType = DefectNormalization.normalizedDefectType(defectType) ?? "field note"
        copy.aiSafetyNotes = DefectNormalization.normalizedValue(aiSafetyNotes)
        copy.transcriptOriginal = DefectNormalization.normalizedValue(transcriptOriginal)
        copy.transcriptEnglish = DefectNormalization.normalizedValue(transcriptEnglish)
        return copy
    }
}
