import Foundation
import ArgumentParser

@main
struct MainCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "minecraft-jar-command",
        abstract: "Run Minecraft",
        subcommands: [RunCommand.self],
        defaultSubcommand: RunCommand.self
    )
}
