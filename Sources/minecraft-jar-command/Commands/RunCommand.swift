//
//  RunCommand.swift
//
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import ArgumentParser
import Common
import InstallationManager

struct RunCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run Minecraft"
    )
    
    @Option(help: "The Minecraft version to download")
    var version: String?
        
    @Flag(help: "Get the most recent snapshot versions of the game when a version isn't manually specified")
    var snapshot = false
    
    @Flag(help: "List available versions")
    var listVersions = false
    
    @Flag(help: "Suppress progress printout")
    var suppressProgress = false
    
    @Option(help: "The directory to save assets and libraries to")
    var workingDirectory: String?
    
    @Option(help: "The directory to start the game in")
    var gameDirectory: String?
    
    @Flag(help: "Use Mojang manifest (no ARM support)")
    var mojangManifest: Bool = false
    
    @Flag(help: "Print the working directory")
    var printWorkingDirectory: Bool = false
    
//    @Option(help: "Switch Java versions")
//    var javaExecutable = "/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home/bin/java"
    
    /*
    @Flag(help: "Print out the new access token before running the game")
    var printAccessToken: Bool = false
    
    @Argument(help: """
        An access token can be obtained from a POST request to
        the Minecraft authentication system. Refer to wiki.vg
        for more information on the /authenticate endpoint:
        https://wiki.vg/Authentication#Authenticate

        You can also use the access token stored in launcher_profiles.json,
        a file generated by the regular Minecraft Launcher.
        """)
    var accessToken: String
    
    @Argument(help: """
        A client token can be obtained from a POST request to
        the Minecraft authentication system. Refer to wiki.vg
        for more information on the /authenticate endpoint:
        https://wiki.vg/Authentication#Authenticate

        You can also use the client token stored in launcher_profiles.json,
        a file generated by the regular Minecraft Launcher.
        """)
    var clientToken: String
     */
    
    mutating func run() async throws {
        let launcherProfilesURL = FileManager
            .default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/minecraft/launcher_profiles.json")
        let launcherProfilesData = try! Data(contentsOf: launcherProfilesURL)
        let launcherProfiles = try! JSONDecoder().decode(LauncherProfiles.self, from: launcherProfilesData)
        
        let gameDirectory = self.gameDirectory != nil ? URL(fileURLWithPath: self.gameDirectory!) : nil
        
        let installationManager: InstallationManager
        if let workingDirectory = workingDirectory {
            installationManager = try InstallationManager(requestedDirectory: URL(fileURLWithPath: workingDirectory), gameDirectory: gameDirectory)
        } else {
            installationManager = try InstallationManager(gameDirectory: gameDirectory)
        }
        
        if printWorkingDirectory {
            print("Working Directory: \(installationManager.baseDirectory.absoluteString)")
        }
        
        if let userRequestedVersion = version {
            installationManager.use(version: .custom(userRequestedVersion))
        } else if snapshot {
            installationManager.use(version: .snapshot)
        } else {
            installationManager.use(version: .release)
        }
        
        do {
            // MARK: Version Info
            if listVersions {
                print("Finding available versions...")
                let versions = try await installationManager.availableVersions(.mojang)
                print("Available versions:")
                for version in versions {
                    print("\t\(version.id)")
                }
                MainCommand.exit()
            }
            
            let versionInfo = try await installationManager.downloadVersionInfo(.mojang)
            guard versionInfo.minimumLauncherVersion >= 21 else {
                print("Unfortunately, \(versionInfo.id) isn't available from this utility")
                print("This utility is only tested with the latest version, and does not work with versions prior to 1.13")
                MainCommand.exit()
            }
            
            try await installationManager.downloadJar()
            let _ = try await installationManager.downloadJava(.mojang)
            
            var lastProgress = 0
            let suppressProgress = self.suppressProgress
            let _ = try await installationManager.downloadAssets { progress in
                if !suppressProgress {
                    let intProgress = Int(progress * 100)
                    if intProgress > lastProgress {
                        lastProgress = intProgress
                        print("\(intProgress)%")
                    }
                }
            }
            let _ = try await installationManager.downloadLibraries()
        } catch let err {
            print("If a network/time-out error occurred, simply restart the program. It will resume where it left off.")
            MainCommand.exit(withError: err)
        }
        if !suppressProgress {
            print("You can hide the progress printout by adding flag: `--suppress-progress`")
        }

        print("Queued up downloads")
        
        try installationManager.copyNatives()
        
        let launchArgumentsResults = installationManager.launchArguments(with: launcherProfiles)
        switch launchArgumentsResults {
            case .success(let args):
                // java
                let javaBundle = installationManager.javaBundle!
                let javaExec = javaBundle.appendingPathComponent("Contents/Home/bin/java", isDirectory: false)
                
                print("Game parameters...")
                let proc = Process()
                proc.executableURL = javaExec
                proc.arguments = args
                proc.currentDirectoryURL = installationManager.baseDirectory

                let pipe = Pipe()
                proc.standardOutput = pipe

                print("Starting game...")
                proc.launch()

                proc.waitUntilExit()
            case .failure(let error):
                MainCommand.exit(withError: error)
        }
        
    }
}
