//
//  RefreshRequest.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

struct RefreshRequest: Encodable {
    let accessToken: String
    let clientToken: String
    let requestUser: Bool
    
    init(accessToken: String, clientToken: String, requestUser: Bool = false) {
        self.accessToken = accessToken
        self.clientToken = clientToken
        self.requestUser = requestUser
    }
}
