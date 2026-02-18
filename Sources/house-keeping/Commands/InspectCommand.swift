import ArgumentParser
import Foundation
import HouseKeeping

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect file metadata",
    )

    @Argument(help: "File path to inspect")
    var path: String

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "Show only tags")
    var tags = false

    @Flag(name: .long, help: "Show only download source")
    var source = false

    func run() throws {
        let expandedPath = Config.expandPath(path)
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            print("Error: File not found: \(expandedPath)")
            throw ExitCode.failure
        }

        let introspector = FileIntrospector()
        let metadata = try introspector.inspect(url: url)

        if tags {
            if metadata.tags.isEmpty {
                print("No tags")
            } else {
                for tag in metadata.tags {
                    print(tag)
                }
            }
            return
        }

        if source {
            if let downloadURL = metadata.downloadURL {
                print(downloadURL)
            } else {
                print("No download source")
            }
            return
        }

        if json {
            let info: [String: Any] = [
                "path": metadata.path,
                "name": metadata.name,
                "extension": metadata.ext,
                "size": metadata.size,
                "size_human": metadata.sizeHuman,
                "is_directory": metadata.isDirectory,
                "creation_date": metadata.creationDate?.description ?? "unknown",
                "modification_date": metadata.modificationDate?.description ?? "unknown",
                "age_days": String(format: "%.1f", metadata.ageDays),
                "tags": metadata.tags,
                "download_url": metadata.downloadURL ?? "",
                "is_quarantined": metadata.isQuarantined,
                "quarantine_agent": metadata.quarantineAgentName ?? "",
                "uti": metadata.uti ?? "",
            ]
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8)
            {
                print(str)
            }
            return
        }

        print("File: \(metadata.name)")
        print("Path: \(metadata.path)")
        print("Size: \(metadata.sizeHuman) (\(metadata.size) bytes)")
        print("Type: \(metadata.isDirectory ? "Directory" : "File")")
        if let uti = metadata.uti {
            print("UTI:  \(uti)")
        }
        print("Created:  \(metadata.creationDate?.description ?? "unknown")")
        print("Modified: \(metadata.modificationDate?.description ?? "unknown")")
        print("Age: \(String(format: "%.1f", metadata.ageDays)) days")
        print("")
        print("Tags: \(metadata.tags.isEmpty ? "none" : metadata.tags.joined(separator: ", "))")
        print("Quarantined: \(metadata.isQuarantined ? "yes" : "no")")
        if let agent = metadata.quarantineAgentName {
            print("Quarantine Agent: \(agent)")
        }
        if let url = metadata.downloadURL {
            print("Download URL: \(url)")
        }
    }
}
