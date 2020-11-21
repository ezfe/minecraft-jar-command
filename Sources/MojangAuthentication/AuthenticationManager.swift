//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct AuthenticationManager {
    static let authenticationURL = URL(string: "https://authserver.mojang.com/authenticate")!
    static let validationURL = URL(string: "https://authserver.mojang.com/validate")!
    static let refreshURL = URL(string: "https://authserver.mojang.com/refresh")!
    
    public static func authenticate(username: String, password: String) throws -> AuthenticateResponse {
        let payload = AuthenticateRequest(username: username, password: password, requestUser: true)
        
        var result: Result<AuthenticateResponse, CError>? = nil
        
        let group = DispatchGroup()
        group.enter()
        yggdrasilPost(url: AuthenticationManager.authenticationURL, body: payload) { (_result: Result<AuthenticateResponse, CError>) in
            result = _result
            group.leave()
        }
        group.wait()
        
        switch result! {
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
