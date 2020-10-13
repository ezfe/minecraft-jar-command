import Foundation
import ArgumentParser

func retrieveData(url: URL) -> Data {
    var foundData: Data? = nil
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
        guard let data = data else {
            print(error?.localizedDescription ?? "Unknown error downloading data")
            Main.exit()
        }

        foundData = data

        semaphore.signal()
    }

    task.resume()
    semaphore.wait()
    return foundData!
}

func getManifest(version: String?) -> VersionManifest.Version {
    let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json")!

    print("Downloading version manifest...")
    let manifestData = retrieveData(url: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let manifest = try? decoder.decode(VersionManifest.self, from: manifestData) else {
        print("Failed to retrieve manifest")
        Main.exit()
    }

    let targetVersion = version ?? manifest.latest.release
    guard let versionManifestEntry = manifest.versions.first(where: {
        $0.id == targetVersion
    }) else {
        print("\(targetVersion) is not a valid Minecraft version")
        Main.exit()
    }

    return versionManifestEntry
}

func downloadClientJAR(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> URL {
    guard let downloadsDict = versionDict.value(forKey: "downloads") as? NSDictionary else {
        print("Failed to parse out downloads dictionary")
        Main.exit()
    }
    guard let clientDownloadDict = downloadsDict.value(forKey: "client") as? NSDictionary else {
        print("Failed to parse out client downloads dictionary")
        Main.exit()
    }

    guard let _cjurl = clientDownloadDict.value(forKey: "url") as? String,
          let clientJARDLURL = URL(string: _cjurl) else {
        print("Failed to parse out client JAR URL")
        Main.exit()
    }

    let clientJarSHA1 = clientDownloadDict.value(forKey: "sha1") as? String
    guard let clientJarSize = clientDownloadDict.value(forKey: "size") as? Int else {
        print("Failed to parse out client JAR size")
        Main.exit()
    }

    let downloadedClientJAR = URL(fileURLWithPath: "client.jar", relativeTo: temporaryDirectoryURL)

    let request = DownloadManager.DownloadRequest(taskName: "Client JAR File",
                                                  remoteURL: clientJARDLURL,
                                                  destinationURL: downloadedClientJAR,
                                                  size: clientJarSize,
                                                  sha1: clientJarSHA1)
    try DownloadManager.shared.download(request)

    return downloadedClientJAR
}

func processArtifact(name: String, downloadsDict: NSDictionary, librariesURL: URL) throws -> LibraryMetadata {
    guard let artifactDict = downloadsDict.value(forKey: "artifact") as? NSDictionary else {
        print("Artifact dictionary missing")
        print(downloadsDict)
        Main.exit()
    }
    guard let _libraryDLURL = artifactDict.value(forKey: "url") as? String,
          let libraryDLURL = URL(string: _libraryDLURL) else {
        print("Failed to parse out library URL")
        print(artifactDict)
        Main.exit()
    }

    let sha1 = artifactDict.value(forKey: "sha1") as? String
    guard let size = artifactDict.value(forKey: "size") as? Int else {
        print("Failed to parse out library size")
        Main.exit()
    }

    guard let pathComponent = artifactDict.value(forKey: "path") as? String else {
        print("Failed to parse out path")
        print(artifactDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    let request = DownloadManager.DownloadRequest(taskName: "Library \(name)",
                                                  remoteURL: libraryDLURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: sha1,
                                                  verbose: false)
    return LibraryMetadata(localURL: destinationURL, isNative: false, downloadRequest: request)
}

func processClassifier(name: String, downloadsDict: NSDictionary, librariesURL: URL) throws -> LibraryMetadata? {

    guard let classifierDict = downloadsDict.value(forKey: "classifiers") as? NSDictionary else {
        print("Found no classifiers, skipping")
        return nil
    }
    let _macosNativesDict = classifierDict.value(forKey: "natives-macos") as? NSDictionary
    let _osxNativesDict = classifierDict.value(forKey: "natives-osx") as? NSDictionary
    guard let macosNativesDict = _macosNativesDict ?? _osxNativesDict else {
        print("Found no macos/osx natives, skipping")
        print(classifierDict)
        return nil
    }
    guard let _nativeDLURL = macosNativesDict.value(forKey: "url") as? String,
          let nativeDLURL = URL(string: _nativeDLURL) else {
        print("Failed to parse out native URL")
        print(macosNativesDict)
        Main.exit()
    }

    let sha1 = macosNativesDict.value(forKey: "sha1") as? String
    guard let size = macosNativesDict.value(forKey: "size") as? Int else {
        print("Failed to parse out natives size")
        Main.exit()
    }

    guard let pathComponent = macosNativesDict.value(forKey: "path") as? String else {
        print("Failed to parse out path")
        print(macosNativesDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(name)",
                                                  remoteURL: nativeDLURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: sha1,
                                                  verbose: false)

    return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
}

func downloadLibrary(libraryDict: NSDictionary, librariesURL: URL) throws -> [LibraryMetadata] {
    guard let name = libraryDict.value(forKey: "name") as? String else {
        print("Library name missing")
        Main.exit()
    }

    print("---")
    print(name)

    if let rules = libraryDict.value(forKey: "rules") as? [NSDictionary] {
        print("Parsing rules...")
        var ruleFailure = false
        for rule in rules {
            let action = rule.value(forKey: "action") as! String
            if let osd = rule.value(forKey: "os") as? NSDictionary {
                let name = osd.value(forKey: "name") as? String
                if action == "allow" && name != "osx" {
                    ruleFailure = true
                    break
                } else if action == "disallow" && name == "osx" {
                    ruleFailure = true
                    break
                }
            }
        }
        if ruleFailure {
            print("Skipping \(name) due to rule")
            return []
        }
    }

    guard let downloadsDict = libraryDict.value(forKey: "downloads") as? NSDictionary else {
        print("Downloads dictionary missing")
        print(libraryDict)
        Main.exit()
    }

    let libmetadata = try processArtifact(name: name, downloadsDict: downloadsDict, librariesURL: librariesURL)
    let nativemetadata = try processClassifier(name: name, downloadsDict: downloadsDict, librariesURL: librariesURL)

    return [libmetadata, nativemetadata].compactMap { $0 }
}

func downloadLibraries(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> [LibraryMetadata] {
    guard let libraryArr = versionDict.value(forKey: "libraries") as? [NSDictionary] else {
        print("Failed to parse out library array")
        Main.exit()
    }

    let libraryURL = URL(fileURLWithPath: "libraries",
                         relativeTo: temporaryDirectoryURL)

    let libraryMetadata = try libraryArr.compactMap { try downloadLibrary(libraryDict: $0, librariesURL: libraryURL) }.joined()

    let requests = libraryMetadata.map { $0.downloadRequest }
    try DownloadManager.shared.download(requests, named: "Libraries")

    return Array(libraryMetadata)
}

func buildAssetRequest(name: String, hash: String, size: Int, assetsObjsDirectoryURL: URL) -> Result<DownloadManager.DownloadRequest, CustomError> {
    let prefix = hash.prefix(2)
    
    guard let downloadURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)") else {
        print("Failed to build URL for \(name)")
        return .failure(CustomError.urlConstructionError)
    }

    let destinationURL = assetsObjsDirectoryURL.appendingPathComponent("\(prefix)/\(hash)")

    let request = DownloadManager.DownloadRequest(taskName: "Asset \(name)",
                                                  remoteURL: downloadURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: hash,
                                                  verbose: false)
    return .success(request)
}

func downloadAssets(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> (assetsDirectory: URL, assetsVersion: String) {
    let assetsDirectoryURL = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: temporaryDirectoryURL)
    let assetsObjsDirectoryURL = assetsDirectoryURL.appendingPathComponent("objects", isDirectory: true)
    let assetsIndxsDirectoryURL = assetsDirectoryURL.appendingPathComponent("indexes", isDirectory: true)

    guard let assetIndexDict = versionDict.value(forKey: "assetIndex") as? NSDictionary else {
        print("Failed to retrieve asset index")
        print(versionDict)
        Main.exit()
    }
    guard let assetIndexId = assetIndexDict.value(forKey: "id") as? String else {
        print("Failed to retrieve asset index ID")
        print(assetIndexDict)
        Main.exit()
    }
    guard let _assetIndexURL = assetIndexDict.value(forKey: "url") as? String,
          let assetIndexURL = URL(string: _assetIndexURL) else {
        print("Failed to retrieve asset index URL")
        print(assetIndexDict)
        Main.exit()
    }

    let decoder = JSONDecoder()
    let indexData = retrieveData(url: assetIndexURL)

    let indexJSONFileURL = assetsIndxsDirectoryURL.appendingPathComponent("\(assetIndexId).json")
    try FileManager.default.createDirectory(at: assetsIndxsDirectoryURL, withIntermediateDirectories: true)
    try indexData.write(to: indexJSONFileURL)

    let index = try decoder.decode(AssetsIndex.self, from: indexData)
    let downloadRequests = index.objects.map { (name, metadata) -> DownloadManager.DownloadRequest in
        let res = buildAssetRequest(name: name, hash: metadata.hash, size: metadata.size, assetsObjsDirectoryURL: assetsObjsDirectoryURL)
        switch res {
        case .success(let request):
            return request
        case .failure(let error):
            print(error)
            Main.exit()
        }
    }

    try DownloadManager.shared.download(downloadRequests, named: "Asset Collection")

    return (assetsObjsDirectoryURL.deletingLastPathComponent(), assetIndexId)
}

func gameArguments(versionDict: NSDictionary,
                   versionName: String,
                   assetsVersion: String,
                   assetsDirectory: URL,
                   gameDirectory: URL) -> String {

    guard let argumentsDict = versionDict.value(forKey: "arguments") as? NSDictionary else {
        print("Missing arguments dictionary")
        print(versionDict)
        Main.exit()
    }
    guard let _gameArgsDict = argumentsDict.value(forKey: "game") as? [Any] else {
        print("Failed to cast/extract game argument list")
        print(argumentsDict)
        Main.exit()
    }
    let gameArgsDict = _gameArgsDict.compactMap { $0 as? String }.map { argument -> String in
        switch argument {
        case "${auth_player_name}":
            return "ezfe"
        case "${version_name}":
            return versionName
        case "${game_directory}":
            return gameDirectory.path
        case "${assets_root}":
            return assetsDirectory.path
        case "${assets_index_name}":
            return assetsVersion
        case "${auth_uuid}":
            return "1e6e79ca12a64a25ae0535cfa0ae576d"
        case "${auth_access_token}":
            return "accesstoken"
        case "${user_type}":
            return "usertype"
        case "${version_type}":
            return "release"
        default:
            return argument
        }
    }
    return gameArgsDict.joined(separator: " ")
}

struct Main: ParsableCommand {
    @Option(help: "The Minecraft version to download")
    var version: String?

    mutating func run() throws {
        let versionManifestEntry = getManifest(version: self.version)

        print("Downloading \(versionManifestEntry.id) package info")
        let versionManifestData = retrieveData(url: versionManifestEntry.url)
        guard let versionDict = try JSONSerialization.jsonObject(with: versionManifestData) as? NSDictionary else {
            print("Failed to download \(versionManifestEntry.id) package info")
            Main.exit()
        }
        guard let mainClassName = versionDict.value(forKey: "mainClass") as? String else {
            print("No main class name")
            print(versionDict)
            Main.exit()
        }

        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                        isDirectory: true)
            .appendingPathComponent("minecraft-jar-command", isDirectory: true)

        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)

        print("\n\nDownloading game files to: \(temporaryDirectoryURL.path).\n\n>>>Press any key to continue")
//        let _ = readLine()

        let clientJAR = try downloadClientJAR(versionDict: versionDict,
                                              temporaryDirectoryURL: temporaryDirectoryURL)

        let (assetsDir, assetsVersion) = try downloadAssets(versionDict: versionDict, temporaryDirectoryURL: temporaryDirectoryURL)

        let libraries = try downloadLibraries(versionDict: versionDict, temporaryDirectoryURL: temporaryDirectoryURL)

        let nativeDirectory = URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: temporaryDirectoryURL)
        if FileManager.default.fileExists(atPath: nativeDirectory.path) {
            try FileManager.default.removeItem(at: nativeDirectory)
        }
        try FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)

        try libraries.filter { $0.isNative }.forEach { libMetadata in
            let target = nativeDirectory.appendingPathComponent(libMetadata.localURL.lastPathComponent)
            try FileManager.default.copyItem(at: libMetadata.localURL, to: target)
        }

        let librariesClassPath = libraries.map { $0.localURL.relativePath }.joined(separator: ":")

        let argsStr = gameArguments(versionDict: versionDict,
                                    versionName: versionManifestEntry.id,
                                    assetsVersion: assetsVersion,
                                    assetsDirectory: assetsDir,
                                    gameDirectory: temporaryDirectoryURL)

        let command = """
            java \
                -Xms1024M \
                -Xmx1024M \
                -XstartOnFirstThread \
                -Djava.library.path=\(nativeDirectory.relativePath) \
                -cp \(librariesClassPath):\(clientJAR.relativePath) \
                \(mainClassName) \
                \(argsStr)
            """

        let launchURL = temporaryDirectoryURL.appendingPathComponent("launch.sh")
        try command.write(to: launchURL, atomically: false, encoding: .utf8)
//        launch(shell: "cd \(temporaryDirectoryURL.path); open .; chmod +x launch.sh; ./launch.sh")
    }
}

Main.main()
//
//print("Minecraft Standalone Launcher")
//
//
