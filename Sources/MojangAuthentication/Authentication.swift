//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct MojangAuth {
    let accessToken: String
    let clientToken: String

    static let validationURL = URL(string: "https://authserver.mojang.com/validate")!
    static let refreshURL = URL(string: "https://authserver.mojang.com/refresh")!

    public init(accessToken: String, clientToken: String) {
        self.accessToken = accessToken
        self.clientToken = clientToken
    }

    public func refresh() throws -> AuthenticationResults? {
        let payload = RefreshPayload(accessToken: self.accessToken, clientToken: self.clientToken, requestUser: true)
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(payload)

        var request = URLRequest(url: MojangAuth.refreshURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = encoded

        var decodedResponse: RefreshResponse? = nil

        let group = DispatchGroup()
        group.enter()
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let decoder = JSONDecoder()
            if let data = data, let decoded = try? decoder.decode(RefreshResponse.self, from: data) {
                decodedResponse = decoded
            }
            group.leave()
        }

        task.resume()
        group.wait()

        guard let response = decodedResponse else {
            return nil
        }

        return AuthenticationResults(username: response.selectedProfile.name,
                                     userId: response.selectedProfile.id,
                                     accessToken: response.accessToken)
    }
}

fileprivate extension MojangAuth {
    struct ValidatePayload: Encodable {
        let accessToken: String
        let clientToken: String
    }

    struct RefreshPayload: Encodable {
        let accessToken: String
        let clientToken: String
        let requestUser: Bool
    }

    struct RefreshResponse: Decodable {
        struct UserInformation: Decodable {
            let username: String
            let id: String
        }

        struct ProfileInformation: Decodable {
            let name: String
            let id: String
        }

        let user: UserInformation
        let selectedProfile: ProfileInformation
        let accessToken: String
        let clientToken: String
    }
}

extension MojangAuth {
    public struct AuthenticationResults {
        public let username: String
        public let userId: String
        public let accessToken: String
    }
}
