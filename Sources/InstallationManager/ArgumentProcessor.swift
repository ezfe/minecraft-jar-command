//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation
import MojangRules

struct ArgumentProcessor {
    private let replacementParameters: [String: String]

    init(versionInfo: VersionPackage,
         installationManager: InstallationManager,
         classPath: String,
         credentials: SignInResult) {
        
        self.replacementParameters = [
            "auth_player_name": credentials.name,
            "version_name": versionInfo.id,
            "game_directory": installationManager.gameDirectory.path,
            "natives_directory": installationManager.nativesDirectory.relativePath,
            "classpath": classPath,
            "assets_root": installationManager.assetsDirectory.relativePath,
            "assets_index_name": versionInfo.assets,
            "auth_uuid": credentials.id,
            "auth_access_token": credentials.token,
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
                guard RuleProcessor.verifyRulesPass(argument.rules, with: .none) else {
                    return nil
                }
                return argument.values.map { applyVariableReplacement(source: $0, parameters: replacementParameters) }
            }

        return processedArguments.joined()
    }
}
