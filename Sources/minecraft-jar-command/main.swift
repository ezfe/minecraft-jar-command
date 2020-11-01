import Foundation
import ArgumentParser

struct Main: ParsableCommand {
    @Option(help: "The Minecraft version to download")
    var version: String?

    @Option(help: "The directory to save assets and libraries to")
    var workingDirectory: String?

    @Option(help: "The directory to start the game in")
    var gameDirectory: String?

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

    mutating func run() throws {
        let auth = AuthenticationManager(accessToken: self.accessToken, clientToken: self.clientToken)
        guard let authResults = try auth.refresh() else {
            Main.exit(withError: CustomError.authenticationFailed)
        }
        if printAccessToken {
            print("New Access Token: \(authResults.accessToken)")
        }

        let versionManifestEntry = getManifest(version: self.version)

        print("Downloading \(versionManifestEntry.id) package info")
        let versionManifestData = retrieveData(url: versionManifestEntry.url)
        guard let versionDict = try JSONSerialization.jsonObject(with: versionManifestData) as? NSDictionary else {
            print("Failed to download \(versionManifestEntry.id) package info")
            Main.exit()
        }
        guard let minimumLauncherVersion = versionDict.value(forKey: "minimumLauncherVersion") as? Int,
              minimumLauncherVersion >= 21 else {
            print("Unfortunately, \(versionManifestEntry.id) isn't available from this utility")
            print("This utility is only tested with the latest version, and does not work with versions prior to 1.13")
            Main.exit()
        }
        guard let mainClassName = versionDict.value(forKey: "mainClass") as? String else {
            print("No main class name")
            print(versionDict)
            Main.exit()
        }

        let workingDirectory: URL
        if let requestedDirectory = self.workingDirectory {
            let requestedDirectoryURL = URL(fileURLWithPath: requestedDirectory)
            try FileManager.default.createDirectory(at: requestedDirectoryURL, withIntermediateDirectories: true)
            workingDirectory = requestedDirectoryURL
        } else {
            workingDirectory = URL(fileURLWithPath: self.workingDirectory ?? NSTemporaryDirectory(),
                                   isDirectory: true)
                .appendingPathComponent("minecraft-jar-command", isDirectory: true)
        }

        let gameDirectory: URL
        if let requestedDirectory = self.gameDirectory {
            let requestedDirectoryURL = URL(fileURLWithPath: requestedDirectory)
            try FileManager.default.createDirectory(at: requestedDirectoryURL, withIntermediateDirectories: true)
            gameDirectory = requestedDirectoryURL
        } else {
            gameDirectory = workingDirectory
        }

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

//        print("\n\nDownloading game files to: \(workingDirectory.path).\n\n>>>Press any key to continue")
//        let _ = readLine()

        let clientJAR = try downloadClientJAR(versionDict: versionDict,
                                              version: versionManifestEntry.id,
                                              temporaryDirectoryURL: workingDirectory)

        let (assetsDir, assetsVersion) = try downloadAssets(versionDict: versionDict, temporaryDirectoryURL: workingDirectory)

        let libraries = try downloadLibraries(versionDict: versionDict, temporaryDirectoryURL: workingDirectory)

        let nativeDirectory = URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: workingDirectory)
        if FileManager.default.fileExists(atPath: nativeDirectory.path) {
            try FileManager.default.removeItem(at: nativeDirectory)
        }
        try FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)

        try libraries.filter { $0.isNative }.forEach { libMetadata in
            let target = nativeDirectory.appendingPathComponent(libMetadata.localURL.lastPathComponent)
            try FileManager.default.copyItem(at: libMetadata.localURL, to: target)
        }

        let librariesClassPath = libraries.map { $0.localURL.relativePath }.joined(separator: ":")
        let classPath = "\(librariesClassPath):\(clientJAR.relativePath)"

        let argumentProcessor = ArgumentProcessor(versionName: versionManifestEntry.id,
                                                  assetsVersion: assetsVersion,
                                                  assetsDirectory: assetsDir,
                                                  gameDirectory: gameDirectory,
                                                  nativesDirectory: nativeDirectory,
                                                  classPath: classPath,
                                                  authResults: authResults)

        let jvmArgsStr = argumentProcessor.jvmArguments(versionDict: versionDict)
        let gameArgsString = argumentProcessor.gameArguments(versionDict: versionDict)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/java")
        proc.arguments = [
            "-Xms1024M",
            "-Xmx1024M",
        ]
        proc.arguments?.append(contentsOf: jvmArgsStr)
        proc.arguments?.append(mainClassName)
        proc.arguments?.append(contentsOf: gameArgsString)

        proc.currentDirectoryURL = workingDirectory

        let pipe = Pipe()
        proc.standardOutput = pipe

        print("Starting game...")
        proc.launch()

        proc.waitUntilExit()
    }
}

Main.main()
