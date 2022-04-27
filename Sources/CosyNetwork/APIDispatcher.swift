//
//  Dispatcher.swift
//  Trooper
//
//  Created by David Jangdal on 2021-03-25.
//

import Foundation
import Combine

public enum APIError: Error {
    case urlRequestUnavailable
}

public struct ResponseError: Error, Decodable {
    public let error: String
    public let errorCode: String
}

public protocol APIDispatcherProtocol {
    func dispatch<Request: APIRequest>(_ request: Request) async throws
    func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> Request.ResponseBodyType 
}

public final class APIDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.urlSession = urlSession
        self.decoder = decoder
    }

    @discardableResult
    private func execute<Request: APIRequest>(_ request: Request) async throws -> Data {
        guard let urlRequest = request.urlRequest else {
            throw APIError.urlRequestUnavailable
        }
        let response = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response.1 as? HTTPURLResponse else {
            throw ResponseError(error: "Could not get HTTPURLResponse from URLRespose", errorCode: "none")
        }

        if httpResponse.statusCode == 400 {
            throw try decoder.decode(ResponseError.self, from: response.0)
        }
        return response.0
    }

    public func dispatch<Request: APIRequest>(_ request: Request) async throws {
        try await execute(request)
    }

    public func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> Request.ResponseBodyType {
        let data = try await execute(request)
        return try decoder.decode(Request.ResponseBodyType.self, from: data)
    }
}

public class APIAuthenticatedDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private var token: String
    private let authHeaderName: String
    private let decoder: JSONDecoder
    
    public init(urlSession: URLSession = .shared, token: String, authHeaderName: String, decoder: JSONDecoder = JSONDecoder()) {
        self.urlSession = urlSession
        self.token = token
        self.authHeaderName = authHeaderName
        self.decoder = decoder
    }

    @discardableResult
    public func execute<Request: APIRequest>(_ request: Request) async throws -> Data {
        guard var urlRequest = request.urlRequest else {
            throw APIError.urlRequestUnavailable
        }
        urlRequest.addValue(token, forHTTPHeaderField: authHeaderName)
        let response = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response.1 as? HTTPURLResponse else {
            throw ResponseError(error: "Could not get HTTPURLResponse from URLRespose", errorCode: "none")
        }

        if let token = httpResponse.value(forHTTPHeaderField: self.authHeaderName) {
            self.token = token
        }

        if httpResponse.statusCode == 400 {
            throw try decoder.decode(ResponseError.self, from: response.0)
        }
        return response.0
    }

    public func dispatch<Request: APIRequest>(_ request: Request) async throws {
        try await execute(request)
    }

    public func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> Request.ResponseBodyType {
        let response = try await execute(request)
        return try decoder.decode(Request.ResponseBodyType.self, from: response)
    }
}
