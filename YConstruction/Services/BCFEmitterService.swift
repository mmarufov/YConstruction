import Foundation
import ZIPFoundation

struct BCFInput: Sendable {
    var topicGuid: String
    var ifcGuid: String?
    var ifcFilename: String

    var title: String
    var description: String
    var topicType: String
    var topicStatus: String
    var priority: String
    var author: String
    var creationDate: Date

    var cameraViewPoint: SIMD3<Double>
    var cameraDirection: SIMD3<Double>
    var cameraUpVector: SIMD3<Double>
    var fieldOfView: Double

    var snapshotPNG: Data?
}

enum BCFEmitterError: Error, LocalizedError {
    case zipCreationFailed
    case directoryCreationFailed
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipCreationFailed: return "Failed to create BCF zip archive"
        case .directoryCreationFailed: return "Failed to create staging directory"
        case .fileWriteFailed(let path): return "Failed to write \(path)"
        }
    }
}

final class BCFEmitterService: Sendable {
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        self.isoFormatter = f
    }

    func emit(_ input: BCFInput, projectId: String) throws -> URL {
        let outputURL = try issuesDirectory(for: projectId)
            .appendingPathComponent("\(input.topicGuid).bcfzip")

        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }

        let topicDir = staging.appendingPathComponent(input.topicGuid, isDirectory: true)
        try FileManager.default.createDirectory(at: topicDir, withIntermediateDirectories: true)

        try writeText(versionXML(), to: staging.appendingPathComponent("bcf.version"))
        try writeText(markupXML(input), to: topicDir.appendingPathComponent("markup.bcf"))
        try writeText(viewpointXML(input), to: topicDir.appendingPathComponent("viewpoint.bcfv"))

        if let png = input.snapshotPNG {
            try png.write(to: topicDir.appendingPathComponent("snapshot.png"))
        }

        try? FileManager.default.removeItem(at: outputURL)
        let archive: Archive
        do {
            archive = try Archive(url: outputURL, accessMode: .create)
        } catch {
            throw BCFEmitterError.zipCreationFailed
        }

        try addEntry(archive: archive, baseURL: staging, relativePath: "bcf.version")
        try addEntry(
            archive: archive,
            baseURL: staging,
            relativePath: "\(input.topicGuid)/markup.bcf"
        )
        try addEntry(
            archive: archive,
            baseURL: staging,
            relativePath: "\(input.topicGuid)/viewpoint.bcfv"
        )
        if input.snapshotPNG != nil {
            try addEntry(
                archive: archive,
                baseURL: staging,
                relativePath: "\(input.topicGuid)/snapshot.png"
            )
        }

        return outputURL
    }

    // MARK: - Convenience

    func emit(from defect: Defect, ifcFilename: String = "duplex.ifc") throws -> URL {
        let input = BCFInput(
            topicGuid: defect.id,
            ifcGuid: defect.guid.isEmpty ? nil : defect.guid,
            ifcFilename: ifcFilename,
            title: "\(defect.defectType) — \(defect.elementType) \(defect.orientation ?? "")".trimmingCharacters(in: .whitespaces),
            description: defectDescription(defect),
            topicType: "Defect",
            topicStatus: defect.resolved ? "Closed" : "Open",
            priority: priority(for: defect.severity),
            author: defect.reporter,
            creationDate: defect.timestamp,
            cameraViewPoint: cameraViewPoint(for: defect),
            cameraDirection: SIMD3(-1, -1, -0.3),
            cameraUpVector: SIMD3(0, 0, 1),
            fieldOfView: 60,
            snapshotPNG: defect.photoPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        )
        return try emit(input, projectId: defect.projectId)
    }

    // MARK: - XML

    private func versionXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Version VersionId="2.1">
            <DetailedVersion>2.1</DetailedVersion>
        </Version>
        """
    }

    private func markupXML(_ i: BCFInput) -> String {
        let date = isoFormatter.string(from: i.creationDate)
        let snapshotXML = i.snapshotPNG == nil ? "" : "\n            <Snapshot>snapshot.png</Snapshot>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Markup>
            <Header>
                <File IfcProject="" IsExternal="true" Filename="\(escape(i.ifcFilename))">
                    <Date>\(date)</Date>
                </File>
            </Header>
            <Topic Guid="\(i.topicGuid)" TopicType="\(escape(i.topicType))" TopicStatus="\(escape(i.topicStatus))">
                <Title>\(escape(i.title))</Title>
                <Priority>\(escape(i.priority))</Priority>
                <CreationDate>\(date)</CreationDate>
                <CreationAuthor>\(escape(i.author))</CreationAuthor>
                <Description>\(escape(i.description))</Description>
            </Topic>
            <Viewpoints Guid="\(UUID().uuidString.lowercased())">
                <Viewpoint>viewpoint.bcfv</Viewpoint>
                \(snapshotXML)
            </Viewpoints>
        </Markup>
        """
    }

    private func viewpointXML(_ i: BCFInput) -> String {
        let selectionXML: String
        if let ifcGuid = i.ifcGuid, !ifcGuid.isEmpty {
            selectionXML = """
                <Selection>
                    <Component IfcGuid="\(escape(ifcGuid))"/>
                </Selection>
            """
        } else {
            selectionXML = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <VisualizationInfo Guid="\(UUID().uuidString.lowercased())">
            <Components>
        \(selectionXML)
                <Visibility DefaultVisibility="true"/>
            </Components>
            <PerspectiveCamera>
                <CameraViewPoint>
                    <X>\(i.cameraViewPoint.x)</X>
                    <Y>\(i.cameraViewPoint.y)</Y>
                    <Z>\(i.cameraViewPoint.z)</Z>
                </CameraViewPoint>
                <CameraDirection>
                    <X>\(i.cameraDirection.x)</X>
                    <Y>\(i.cameraDirection.y)</Y>
                    <Z>\(i.cameraDirection.z)</Z>
                </CameraDirection>
                <CameraUpVector>
                    <X>\(i.cameraUpVector.x)</X>
                    <Y>\(i.cameraUpVector.y)</Y>
                    <Z>\(i.cameraUpVector.z)</Z>
                </CameraUpVector>
                <FieldOfView>\(i.fieldOfView)</FieldOfView>
            </PerspectiveCamera>
        </VisualizationInfo>
        """
    }

    // MARK: - Filesystem

    private func issuesDirectory(for projectId: String) throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId)
            .appendingPathComponent("issues")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStagingDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw BCFEmitterError.fileWriteFailed(url.lastPathComponent)
        }
        try data.write(to: url)
    }

    private func addEntry(archive: Archive, baseURL: URL, relativePath: String) throws {
        try archive.addEntry(
            with: relativePath,
            relativeTo: baseURL,
            compressionMethod: .deflate
        )
    }

    // MARK: - Helpers

    private func defectDescription(_ d: Defect) -> String {
        var lines: [String] = []
        if let s = d.transcriptOriginal { lines.append("Original: \(s)") }
        if let e = d.transcriptEnglish { lines.append("English: \(e)") }
        lines.append("Location: \(d.storey) > \(d.space ?? "—") > \(d.orientation ?? "—") \(d.elementType)")
        if let n = d.aiSafetyNotes { lines.append("AI safety notes: \(n)") }
        return lines.joined(separator: "\n")
    }

    private func cameraViewPoint(for d: Defect) -> SIMD3<Double> {
        SIMD3(d.centroidX + 5, d.centroidY + 5, d.centroidZ + 2)
    }

    private func priority(for severity: Severity) -> String {
        switch severity {
        case .low: return "Low"
        case .medium: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    private func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
