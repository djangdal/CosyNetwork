//
//  Dispatcher.swift
//
//  Created by David Jangdal on 2021-03-25.
//

import Foundation
import Combine

public enum APIError: Error {
    case invdalidHttpResponse
    case couldNotCreateHTTPStatusCode
    case statusCodeNotHandled
}

public protocol APIDispatcherProtocol {
    @discardableResult func dispatch<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode)
    func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> (Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode)
}

open class APIDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.urlSession = urlSession
        self.decoder = decoder
    }

    @discardableResult
    private func execute<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode) {
        let urlRequest = try request.urlRequest
        let response = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response.1 as? HTTPURLResponse else {
            throw APIError.invdalidHttpResponse
        }

        guard let statusCode = HTTPStatusCode(rawValue: httpResponse.statusCode) else {
            throw APIError.couldNotCreateHTTPStatusCode
        }

        if request.failingStatusCodes.contains(statusCode) {
            throw try decoder.decode(Request.ErrorBodyType.self, from: response.0)
        }
        return (response.0, httpResponse, statusCode)
    }

    @discardableResult
    open func dispatch<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode) {
        try await execute(request)
    }

    open func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> (Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode) {
        let (data, urlResponse, statusCode) = try await execute(request)

        if request.successStatusCodes.contains(statusCode) {
            return (try decoder.decode(Request.ResponseBodyType.self, from: data), urlResponse, statusCode)
        }

        throw APIError.statusCodeNotHandled
    }
}
