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

        let shaSum = self.shaSum
        
        let group = DispatchGroup()
        group.enter()
        async {
            let mojangVersion = try await mojangManager.downloadVersionInfo(url: mojangManifest)
            let armVersion = try await customManager.downloadVersionInfo(url: armManifest)

            var newVersion = armVersion
            
            newVersion.id = "\(mojangVersion.id)-arm64"
            newVersion.downloads = mojangVersion.downloads
            newVersion.time = mojangVersion.time
            newVersion.releaseTime = mojangVersion.releaseTime
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try! encoder.encode(newVersion)
            
            if shaSum {
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
            
            group.leave()
        }
        group.wait()
    }
}
