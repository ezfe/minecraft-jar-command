//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation
import MojangAuthentication

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

    func jvmArguments(versionDict: NSDictionary) -> FlattenSequence<[[String]]> {
        guard let unprocessedArray = versionDict.value(forKeyPath: "arguments.jvm") as? [Any] else {
            print("Missing game arguments")
            print(versionDict)
            Main.exit()
        }

        return self.process(arguments: unprocessedArray)
    }

    func gameArguments(versionDict: NSDictionary) -> FlattenSequence<[[String]]> {
        guard let unprocessedArray = versionDict.value(forKeyPath: "arguments.game") as? [Any] else {
            print("Missing JVM arguments")
            print(versionDict)
            Main.exit()
        }

        return self.process(arguments: unprocessedArray)
    }

    private func process(arguments: [Any]) -> FlattenSequence<[[String]]> {
        let processedArguments = arguments
            .compactMap { el -> WrappedArgument? in
                if let str = el as? String {
                    return WrappedArgument.simple(str)
                } else if let obj = el as? NSDictionary {
                    return WrappedArgument.complex(obj)
                } else {
                    return nil
                }
            }
            .compactMap { argument -> [String]? in
                switch argument {
                case .simple(let str):
                    return [applyVariableReplacement(source: str, parameters: replacementParameters)]
                case .complex(let dict):
                    guard let rulesArr = dict.value(forKey: "rules") as? [NSDictionary],
                          let parametersArr = dict.value(forKey: "value") as? [String],
                          RuleProcessor.verifyRulePasses(rulesArr) else {

                        return nil
                    }
                    return parametersArr.map { applyVariableReplacement(source: $0, parameters: replacementParameters) }
                }
            }

        return processedArguments.joined()
    }

    enum WrappedArgument {
        case simple(String)
        case complex(NSDictionary)
    }
}
