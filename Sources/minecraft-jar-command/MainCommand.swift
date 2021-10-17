import Foundation
import ArgumentParser
import MojangAuthentication

@main
struct MainCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "minecraft-jar-command",
        abstract: "Run Minecraft",
        subcommands: [LoginCommand.self, RunCommand.self, SyncCommand.self],
        defaultSubcommand: RunCommand.self
    )
}
