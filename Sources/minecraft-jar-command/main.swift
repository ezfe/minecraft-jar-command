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
    guard let clientJarSHA1 = clientDownloadDict.value(forKey: "sha1") as? String else {
        print("Failed to parse out client JAR SHA1")
        Main.exit()
    }


    let downloadedClientJAR = URL(fileURLWithPath: "client.jar", relativeTo: temporaryDirectoryURL)

    let dl = DownloadManager.shared
    try dl.download(taskName: "Client JAR File", from: clientJARDLURL, to: downloadedClientJAR, sha1: clientJarSHA1)

    return downloadedClientJAR
}

func processArtifact(name: String, downloadsDict: NSDictionary, librariesURL: URL) throws -> URL {
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
    guard let librarySHA1 = artifactDict.value(forKey: "sha1") as? String else {
        print("Failed to parse out library SHA1")
        print(artifactDict)
        Main.exit()
    }
    guard let pathComponent = artifactDict.value(forKey: "path") as? String else {
        print("Failed to parse out path")
        print(artifactDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    let dl = DownloadManager.shared
    try dl.download(taskName: "Library \(name)", from: libraryDLURL, to: destinationURL, sha1: librarySHA1)

    return destinationURL
}

func processClassifier(name: String, downloadsDict: NSDictionary, librariesURL: URL) throws -> URL? {
    guard let classifierDict = downloadsDict.value(forKey: "classifiers") as? NSDictionary else {
        print("Found no classifiers, skipping")
        print(downloadsDict)
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
    guard let pathComponent = macosNativesDict.value(forKey: "path") as? String else {
        print("Failed to parse out path")
        print(macosNativesDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        print("\(name) already downloaded")
        print("Skipping...")
        return destinationURL
    }

    try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let semaphore = DispatchSemaphore(value: 0)

    let download = URLSession.shared.downloadTask(with: nativeDLURL) { (fileURL, response, error) in
        guard let fileURL = fileURL else {
            print(error?.localizedDescription ?? "Unknown error downloading natives for \(name)")
            print(nativeDLURL)
            Main.exit()
        }

        print("Finished downloading natives for \(name)")
        try! FileManager.default.moveItem(at: fileURL, to: destinationURL)
        semaphore.signal()
    }

    print("Downloading natives for \(name)")
    download.resume()
    semaphore.wait()

    return destinationURL
}

func downloadLibrary(libraryDict: NSDictionary, librariesURL: URL) throws -> LibraryInformation? {
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
            return nil
        }
    }

    guard let downloadsDict = libraryDict.value(forKey: "downloads") as? NSDictionary else {
        print("Downloads dictionary missing")
        print(libraryDict)
        Main.exit()
    }

    let liburl = try processArtifact(name: name, downloadsDict: downloadsDict, librariesURL: librariesURL)
    let nativeurl = try processClassifier(name: name, downloadsDict: downloadsDict, librariesURL: librariesURL)

//    print(downloadsDict)
//    print(liburl)
//    print(nativeurl?.description ?? "no native file")

    return LibraryInformation(url: liburl, native: nativeurl)
}

func downloadLibraries(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> [LibraryInformation] {
    guard let libraryArr = versionDict.value(forKey: "libraries") as? [NSDictionary] else {
        print("Failed to parse out library array")
        Main.exit()
    }

    let libraryURL = URL(fileURLWithPath: "libraries",
                         relativeTo: temporaryDirectoryURL)

    return try libraryArr.compactMap { try downloadLibrary(libraryDict: $0, librariesURL: libraryURL) }
}

func downloadAsset(name: String, hash: String, assetsObjsDirectoryURL: URL) throws {
    let prefix = hash.prefix(2)
    guard let downloadURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)") else {
        print("Failed to build URL for \(name)")
        Main.exit()
    }

    let destinationURL = assetsObjsDirectoryURL.appendingPathComponent("\(prefix)/\(hash)", isDirectory: true)

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        print("\(name) already downloaded")
        print("Skipping...")
        return
    }

    try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let semaphore = DispatchSemaphore(value: 0)

    let download = URLSession.shared.downloadTask(with: downloadURL) { (fileURL, response, error) in
        guard let fileURL = fileURL else {
            print(error?.localizedDescription ?? "Unknown error downloading asset \(name)")
            print(downloadURL)
            Main.exit()
        }

        print("Finished downloading asset \(name)")
        try! FileManager.default.moveItem(at: fileURL, to: destinationURL)
        semaphore.signal()
    }

    print("Downloading asset \(name)")
    download.resume()
    semaphore.wait()
}

func downloadAssets(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> (URL, String) {
    print(versionDict)

    let assetsDirectoryURL = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: temporaryDirectoryURL)
    let assetsObjsDirectoryURL = assetsDirectoryURL.appendingPathComponent("objects", isDirectory: true)
    let assetsIndxsDirectoryURL = assetsDirectoryURL.appendingPathComponent("indexes", isDirectory: true)

    guard let assetVersion = versionDict.value(forKey: "assets") as? String else {
        print("Failed to retrieve assets version")
        print(versionDict)
        Main.exit()
    }
    guard let assetIndexDict = versionDict.value(forKey: "assetIndex") as? NSDictionary else {
        print("Failed to retrieve asset index")
        print(versionDict)
        Main.exit()
    }
//    guard let assetIndexId = assetIndexDict.value(forKey: "id") as? String else {
//        print("Failed to retrieve asset index ID")
//        print(assetIndexDict)
//        Main.exit()
//    }
    guard let _assetIndexURL = assetIndexDict.value(forKey: "url") as? String,
          let assetIndexURL = URL(string: _assetIndexURL) else {
        print("Failed to retrieve asset index URL")
        print(assetIndexDict)
        Main.exit()
    }

    let decoder = JSONDecoder()
    let indexData = retrieveData(url: assetIndexURL)

    let indexJSONFileURL = assetsIndxsDirectoryURL.appendingPathComponent("\(assetVersion).json")
    try FileManager.default.createDirectory(at: assetsIndxsDirectoryURL, withIntermediateDirectories: true)
    try indexData.write(to: indexJSONFileURL)

    let index = try decoder.decode(AssetsIndex.self, from: indexData)

    let group = DispatchGroup()
    let queue = DispatchQueue(label: "asset-downloading")

    for (name, metadata) in index.objects {
        group.enter()
        queue.async {
            do {
                try downloadAsset(name: name, hash: metadata.hash, assetsObjsDirectoryURL: assetsObjsDirectoryURL)
            } catch let err {
                print(err.localizedDescription)
            }
            group.leave()
        }
    }

    group.wait()
    return (assetsObjsDirectoryURL.deletingLastPathComponent(), assetVersion)
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
        let _ = readLine()

        let clientJAR = try downloadClientJAR(versionDict: versionDict,
                                              temporaryDirectoryURL: temporaryDirectoryURL)

        let (assetsDir, assetsVersion) = try downloadAssets(versionDict: versionDict, temporaryDirectoryURL: temporaryDirectoryURL)

        let libs = try downloadLibraries(versionDict: versionDict, temporaryDirectoryURL: temporaryDirectoryURL)

        let nativeDirectory = URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: temporaryDirectoryURL)
        if FileManager.default.fileExists(atPath: nativeDirectory.path) {
            try FileManager.default.removeItem(at: nativeDirectory)
        }
        try FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)
        for lib in libs {
            if let native = lib.native {
                let target = nativeDirectory.appendingPathComponent(native.lastPathComponent)
                try FileManager.default.copyItem(at: native, to: target)
            }
        }

        let libsCP = libs.map { $0.url.relativePath }.joined(separator: ":")
        let nativesCP = libs.compactMap { $0.native?.relativePath }.joined(separator: ":")

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
                -cp \(libsCP):\(nativesCP):\(clientJAR.relativePath) \
                \(mainClassName) \
                \(argsStr)
            """

        let launchURL = temporaryDirectoryURL.appendingPathComponent("launch.sh")
        try command.write(to: launchURL, atomically: false, encoding: .utf8)
        launch(shell: "cd \(temporaryDirectoryURL.path); open .; chmod +x launch.sh; ./launch.sh")
    }
}

Main.main()
//
//print("Minecraft Standalone Launcher")
//
//
