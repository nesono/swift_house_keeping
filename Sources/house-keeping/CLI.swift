import ArgumentParser
import Foundation

@main
struct HouseKeepingCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "house_keeping",
        abstract: "macOS file management daemon — watches folders and acts on files based on configurable rules.",
        version: "0.1.0",
        subcommands: [
            DaemonCommand.self,
            CheckCommand.self,
            ListCommand.self,
            RunCommand.self,
            DryRunCommand.self,
            StatusCommand.self,
            InspectCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
        ]
    )
}
