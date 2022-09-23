//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation

public struct RuleProcessor {
	public struct FeatureSet: OptionSet {
		public let rawValue: Int
		
		public init(rawValue: Int) {
			self.rawValue = rawValue
		}
		
		public static let hasCustomResolution = FeatureSet(rawValue: 1 << 0)
		public static let isDemoUser = FeatureSet(rawValue: 1 << 1)
		
		static let all: FeatureSet = [.hasCustomResolution, .isDemoUser]
		public static let none: FeatureSet = []
	}
	
	/**
	 * Process a list of rules
	 *
	 * - Parameters:
	 *   - rules: The list of clauses in the rule
	 * - Returns: A boolean indicating whether the rules passed (`true`) or not (`false`)
	 */
	public static func verifyRulesPass(_ clauses: [Rule]?, with enabledFeatures: FeatureSet) -> Bool {
		guard let clauses = clauses else { return true }
		if clauses.isEmpty { return true }
		
		var ruleFailure = true
		for rule in clauses {
			if let osName = rule.os?.name {
				if !(["osx", "macos"].contains(osName)) {
					// skip this rule modifier
					continue
				}
			}
			
			// osRule.version is currently unchecked
			
			if let arch = rule.os?.arch {
				if arch != "x86" {
					continue
				}
			}
			
			if let demoUserConstraint = rule.features?.isDemoUser {
				if enabledFeatures.contains(.isDemoUser) != demoUserConstraint {
					continue
				}
			}
			
			if let hasCustomResConstraint = rule.features?.hasCustomResolution {
				if enabledFeatures.contains(.hasCustomResolution) != hasCustomResConstraint {
					continue
				}
			}
			
			// apply this rule modifier
			switch rule.action {
				case .allow:
					ruleFailure = false
				case .disallow:
					ruleFailure = true
			}
		}
		return !ruleFailure
	}
}
