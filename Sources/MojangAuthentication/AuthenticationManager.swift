//
//  AuthenticationManager.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common

public struct AuthenticationManager {
    static let authenticationURL = URL(string: "https://authserver.mojang.com/authenticate")!
    static let validationURL = URL(string: "https://authserver.mojang.com/validate")!
    static let refreshURL = URL(string: "https://authserver.mojang.com/refresh")!
    
    public static func authenticate(username: String,
                                    password: String,
                                    clientToken: String? = nil) throws -> AuthenticateResponse {
        let payload = AuthenticateRequest(username: username, password: password, clientToken: clientToken, requestUser: true)
        
        let result: Result<AuthenticateResponse, CError>
        result = yggdrasilPost(url: AuthenticationManager.authenticationURL, body: payload)
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
    
    public static func authenticate(username: String,
                                    password: String,
                                    clientToken: String? = nil,
                                    callback: @escaping (Result<AuthenticateResponse, CError>) -> Void) {

        let payload = AuthenticateRequest(username: username, password: password, clientToken: clientToken, requestUser: true)
        
        yggdrasilPost(url: AuthenticationManager.authenticationURL, body: payload, callback: callback)
    }
    
    public static func refresh(accessToken: String, clientToken: String) throws -> RefreshResponse {
        let payload = RefreshRequest(accessToken: accessToken, clientToken: clientToken, requestUser: true)
        
        let result: Result<RefreshResponse, CError>
        result = yggdrasilPost(url: AuthenticationManager.refreshURL, body: payload)
    
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }

    }

//    public func refresh() throws -> AuthenticationResults? {
//        let payload = RefreshPayload(accessToken: self.accessToken, clientToken: self.clientToken, requestUser: true)
//        let encoder = JSONEncoder()
//
//        var request = URLRequest(url: AuthenticationManager.refreshURL)
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpMethod = "POST"
//        request.httpBody = try encoder.encode(payload)
//
//        var decodedResponse: RefreshResponse? = nil
//
//        let group = DispatchGroup()
//        group.enter()
//        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
//            let decoder = JSONDecoder()
//            if let data = data, let decoded = try? decoder.decode(RefreshResponse.self, from: data) {
//                decodedResponse = decoded
//            }
//            group.leave()
//        }
//
//        task.resume()
//        group.wait()
//
//        guard let response = decodedResponse else {
//            return nil
//        }
//
//        return AuthenticationResults(username: response.selectedProfile.name,
//                                     userId: response.selectedProfile.id,
//                                     accessToken: response.accessToken)
//    }
}
