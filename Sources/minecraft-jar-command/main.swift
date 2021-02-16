import Foundation
import ArgumentParser
import MojangAuthentication

struct Main: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "minecraft-jar-command",
        abstract: "Run Minecraft",
        subcommands: [LoginCommand.self, RunCommand.self, ArmPatchCommand.self],
        defaultSubcommand: RunCommand.self
    )
}

Main.main()
