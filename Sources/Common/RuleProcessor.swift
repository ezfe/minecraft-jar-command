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
    public static func verifyRulePasses(_ clauses: [NSDictionary]) -> Bool {
        var ruleFailure = true
        for rule in clauses {
            guard let action = rule.value(forKey: "action") as? String else { continue }

            if let osd = rule.value(forKey: "os") as? NSDictionary {
                let name = osd.value(forKey: "name") as? String
                if !(name == "osx" || name == "macos") {
                    // skip this rule modifier
                    continue
                }
            }

            // apply this rule modifier
            if action == "allow" {
                ruleFailure = false
            } else if action == "disallow" {
                ruleFailure = true
            } else {
                print("Unsure how to handle rule action= \(action)")
                continue
            }
        }
        return !ruleFailure
    }
}
