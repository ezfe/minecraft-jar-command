//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation
import MojangAuthentication
import InstallationManager
import Rules

struct ArgumentProcessor {
    private let replacementParameters: [String: String]

    init(versionName: String,
         assetsVersion: String,
         assetsDirectory: URL,
         gameDirectory: URL,
         nativesDirectory: URL,
         classPath: String,
         authResults: RefreshResponse) {

        self.replacementParameters = [
            "auth_player_name": authResults.selectedProfile.name,
            "version_name": versionName,
            "game_directory": gameDirectory.path,
            "natives_directory": nativesDirectory.relativePath,
            "classpath": classPath,
            "assets_root": assetsDirectory.relativePath,
            "assets_index_name": assetsVersion,
            "auth_uuid": authResults.selectedProfile.id,
            "auth_access_token": authResults.accessToken,
            "user_type": "usertype",
            "version_type": "release"
        ]
    }

    func jvmArguments(versionInfo: VersionPackage) -> FlattenSequence<[[String]]> {
        return self.process(arguments: versionInfo.arguments.jvm)
    }

    func gameArguments(versionInfo: VersionPackage) -> FlattenSequence<[[String]]> {
        return self.process(arguments: versionInfo.arguments.game)
    }

    private func process(arguments: [VersionPackage.Arguments.Argument]) -> FlattenSequence<[[String]]> {
        let processedArguments = arguments
            .compactMap { argument -> [String]? in
                guard RuleProcessor.verifyRulesPass(argument.rules) else {
                    return nil
                }
                return argument.values.map { applyVariableReplacement(source: $0, parameters: replacementParameters) }
            }

        return processedArguments.joined()
    }
}
