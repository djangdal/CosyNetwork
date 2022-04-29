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

    private func data(from request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: APIError.invdalidHttpResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }.resume()
        }
    }

    @discardableResult
    private func execute<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode) {
        let urlRequest = try request.urlRequest

        let response: (Data, URLResponse)
        if #available(iOS 15.0, *) {
            response = try await urlSession.data(for: urlRequest)
        } else {
            response = try await data(from: urlRequest)
        }

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
        let (data, urlResponse, statusCode) = try await execute(request)
        guard request.successStatusCodes.contains(statusCode) else {
            throw APIError.statusCodeNotHandled
        }
        return (data, urlResponse, statusCode)
    }

    open func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> (Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode) {
        let (data, urlResponse, statusCode) = try await execute(request)

        if request.successStatusCodes.contains(statusCode) {
            return (try decoder.decode(Request.ResponseBodyType.self, from: data), urlResponse, statusCode)
        }

        throw APIError.statusCodeNotHandled
    }
}
