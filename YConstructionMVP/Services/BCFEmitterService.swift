import Foundation

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

    var cameraViewPoint: (x: Double, y: Double, z: Double)
    var cameraDirection: (x: Double, y: Double, z: Double)
    var cameraUpVector: (x: Double, y: Double, z: Double)
    var fieldOfView: Double

    var snapshotPNG: Data?
    var snapshotFilename: String?
}

enum BCFEmitterError: LocalizedError {
    case archiveCreationFailed
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .archiveCreationFailed:
            return "Failed to create the local BCF archive."
        case .directoryCreationFailed:
            return "Failed to prepare the local BCF directory."
        }
    }
}

final class BCFEmitterService {
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        isoFormatter = formatter
    }

    func emit(_ input: BCFInput, to outputURL: URL) throws -> URL {
        let topicDirectory = input.topicGuid
        let versionData = Data(versionXML().utf8)
        let markupData = Data(markupXML(input).utf8)
        let viewpointData = Data(viewpointXML(input).utf8)
        let snapshotName = input.snapshotFilename ?? "snapshot.png"

        var entries: [SimpleZipWriter.Entry] = [
            .init(path: "bcf.version", data: versionData),
            .init(path: "\(topicDirectory)/markup.bcf", data: markupData),
            .init(path: "\(topicDirectory)/viewpoint.bcfv", data: viewpointData)
        ]

        if let snapshotPNG = input.snapshotPNG {
            entries.append(.init(path: "\(topicDirectory)/\(snapshotName)", data: snapshotPNG))
        }

        let parent = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw BCFEmitterError.directoryCreationFailed
        }

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try SimpleZipWriter.write(entries: entries, to: outputURL)
            return outputURL
        } catch {
            throw BCFEmitterError.archiveCreationFailed
        }
    }

    private func versionXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Version VersionId="2.1">
            <DetailedVersion>2.1</DetailedVersion>
        </Version>
        """
    }

    private func markupXML(_ input: BCFInput) -> String {
        let date = isoFormatter.string(from: input.creationDate)
        let snapshotName = input.snapshotFilename ?? "snapshot.png"
        let snapshotXML = input.snapshotPNG == nil ? "" : "\n            <Snapshot>\(escape(snapshotName))</Snapshot>"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Markup>
            <Header>
                <File IfcProject="" IsExternal="true" Filename="\(escape(input.ifcFilename))">
                    <Date>\(date)</Date>
                </File>
            </Header>
            <Topic Guid="\(input.topicGuid)" TopicType="\(escape(input.topicType))" TopicStatus="\(escape(input.topicStatus))">
                <Title>\(escape(input.title))</Title>
                <Priority>\(escape(input.priority))</Priority>
                <CreationDate>\(date)</CreationDate>
                <CreationAuthor>\(escape(input.author))</CreationAuthor>
                <Description>\(escape(input.description))</Description>
            </Topic>
            <Viewpoints Guid="\(UUID().uuidString.lowercased())">
                <Viewpoint>viewpoint.bcfv</Viewpoint>
                \(snapshotXML)
            </Viewpoints>
        </Markup>
        """
    }

    private func viewpointXML(_ input: BCFInput) -> String {
        let selectionXML: String
        if let ifcGuid = input.ifcGuid, !ifcGuid.isEmpty {
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
                    <X>\(input.cameraViewPoint.x)</X>
                    <Y>\(input.cameraViewPoint.y)</Y>
                    <Z>\(input.cameraViewPoint.z)</Z>
                </CameraViewPoint>
                <CameraDirection>
                    <X>\(input.cameraDirection.x)</X>
                    <Y>\(input.cameraDirection.y)</Y>
                    <Z>\(input.cameraDirection.z)</Z>
                </CameraDirection>
                <CameraUpVector>
                    <X>\(input.cameraUpVector.x)</X>
                    <Y>\(input.cameraUpVector.y)</Y>
                    <Z>\(input.cameraUpVector.z)</Z>
                </CameraUpVector>
                <FieldOfView>\(input.fieldOfView)</FieldOfView>
            </PerspectiveCamera>
        </VisualizationInfo>
        """
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private enum SimpleZipWriter {
    struct Entry {
        let path: String
        let data: Data
    }

    static func write(entries: [Entry], to outputURL: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc32 = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)

            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc32)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(crc32)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(offset)
            centralDirectory.append(nameData)

            offset = UInt32(archive.count)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        let centralDirectorySize = UInt32(centralDirectory.count)
        let entryCount = UInt16(entries.count)

        archive.append(centralDirectory)
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(entryCount)
        archive.appendLE(entryCount)
        archive.appendLE(centralDirectorySize)
        archive.appendLE(centralDirectoryOffset)
        archive.appendLE(UInt16(0))

        try archive.write(to: outputURL, options: .atomic)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                if (value & 1) == 1 {
                    value = 0xEDB88320 ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let lookupIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[lookupIndex] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}
