//
//  RunCommand.swift
//
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import MojangAuthentication
import ArgumentParser
import Common
import InstallationManager
import Crypto

struct ArmPatchCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "patch",
        abstract: "Apply ARM Patch"
    )
    
    @Flag
    var shaSum = false
    
    mutating func run() throws {
        let mojangManifest = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
        let armManifest = URL(string: "https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/version_manifest_v2.json")!

        let mojangManager = try InstallationManager()
        mojangManager.use(version: .snapshot)
        
        let customManager = try InstallationManager()
        customManager.use(version: .snapshot)

        var _mojangVersion: VersionPackage? = nil
        var _armVersion: VersionPackage? = nil
        
        let group = DispatchGroup()
        group.enter()
        customManager.downloadVersionInfo(url: armManifest) { armResult in
            switch armResult {
                case .success(let version):
                    _armVersion = version
                case .failure(let error):
                    Main.exit(withError: error)
            }
            group.leave()
        }

        group.enter()
        mojangManager.downloadVersionInfo(url: mojangManifest) { mojangResult in
            switch mojangResult {
                case .success(let version):
                    _mojangVersion = version
                case .failure(let error):
                    Main.exit(withError: error)
            }
            
            group.leave()
        }
        
        group.wait()

        
        guard let armVersion = _armVersion, let mojangVersion = _mojangVersion else {
            Main.exit()
        }
    
        var newVersion = armVersion
        
        newVersion.id = mojangVersion.id
        newVersion.downloads = mojangVersion.downloads
        newVersion.time = mojangVersion.time
        newVersion.releaseTime = mojangVersion.releaseTime
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try! encoder.encode(newVersion)
        
        if self.shaSum {
            let hashed = Insecure.SHA1.hash(data: data)
            
            print(hashed.description)

            struct NeededValues: Encodable {
                let id: String
                let time: Date
                let releaseTime: Date
            }
            let neededValues = NeededValues(id: newVersion.id,
                                            time: newVersion.time,
                                            releaseTime: newVersion.releaseTime)
            let encoded = try encoder.encode(neededValues)
            let stringValue = String(data: encoded, encoding: .utf8)!
                .dropFirst()
                .dropLast()
                .replacingOccurrences(of: ",", with: ",\n")
                .appending(",")
            print(stringValue)
        } else {
            let string = String(data: data, encoding: .utf8)!
            print(string)
        }

    }
}
