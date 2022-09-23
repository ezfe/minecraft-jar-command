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
	
	func jvmArguments(versionInfo: VersionPackage) -> any Sequence<String> {
		if let versionInfo = versionInfo as? VersionPackage21 {
			return self.process(arguments: versionInfo.arguments.jvm)
		} else {
			let arguments = [
				"-XstartOnFirstThread",
				"-Xss1M",
				"-Djava.library.path=${natives_directory}",
				"-Dminecraft.launcher.brand=${launcher_name}",
				"-Dminecraft.launcher.version=${launcher_version}",
				"-cp", "${classpath}",
			]
			return self.process(arguments: arguments)
		}
	}
	
	func gameArguments(versionInfo: VersionPackage) -> any Sequence<String> {
		if let versionInfo = versionInfo as? VersionPackage21 {
			return self.process(arguments: versionInfo.arguments.game)
		} else if let versionInfo = versionInfo as? VersionPackage14 {
			let arguments = versionInfo.gameArguments.split(separator: " ").map { String($0) }
			return self.process(arguments: arguments)
		} else {
			print("Failed to process game arguments!", versionInfo)
			return []
		}
	}
	
	private func process(arguments: [String]) -> [String] {
		return arguments.map { applyVariableReplacement(source: $0, parameters: replacementParameters) }
	}
	
	private func process(arguments: [VersionPackage21.Arguments.Argument]) -> FlattenSequence<[[String]]> {
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
