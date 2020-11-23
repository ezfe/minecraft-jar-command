//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation

public struct RuleProcessor {
    /**
     * Process a list of rules
     *
     * - Parameters:
     *   - rules: The list of clauses in the rule
     * - Returns: A boolean indicating whether the rules passed (`true`) or not (`false`)
     */
    public static func verifyRulesPass(_ clauses: [Rule]) -> Bool {
        if clauses.isEmpty { return true }
        
        var ruleFailure = true
        for rule in clauses {
            if let osRule = rule.os {
                if let name = osRule.name {
                    if !(["osx", "macos"].contains(name)) {
                        // skip this rule modifier
                        continue
                    }
                } else if let arch = osRule.arch {
                    if arch != "x86" {
                        continue
                    }
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
