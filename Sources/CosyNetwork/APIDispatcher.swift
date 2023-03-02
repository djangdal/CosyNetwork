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
    @available(iOS 13.0.0, *)
    @discardableResult func dispatch<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode)
    @available(iOS 13.0.0, *)
    func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> (Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode)

    func dispatch<Request: APIDecodableRequest>(
        _ request: Request,
        completion: @escaping (Result<(Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode), Error>) -> ())
}

open class APIDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared, decoder: JSONDecoder) {
        self.urlSession = urlSession
        self.decoder = decoder
    }
}

public extension APIDispatcher {
    @available(iOS 13.0.0, *)
    @discardableResult
    func dispatch<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode) {
        let (data, urlResponse, statusCode) = try await execute(request)
        guard request.successStatusCodes.contains(statusCode) else {
            throw APIError.statusCodeNotHandled
        }
        return (data, urlResponse, statusCode)
    }

    @available(iOS 13.0.0, *)
    func dispatch<Request: APIDecodableRequest>(_ request: Request) async throws -> (Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode) {
        let (data, urlResponse, statusCode) = try await execute(request)

        if request.successStatusCodes.contains(statusCode) {
            return (try decoder.decode(Request.ResponseBodyType.self, from: data), urlResponse, statusCode)
        }

        throw APIError.statusCodeNotHandled
    }
}

private extension APIDispatcher {
    func data(from request: URLRequest, completion: @escaping (Result<(Data, URLResponse), Error>) -> ()) {
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let response = response else {
                completion(.failure(APIError.invdalidHttpResponse))
                return
            }
            completion(.success((data, response)))
        }).resume()
    }

    @available(iOS 13.0.0, *)
    func data(from request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            data(from: request) { result in
                continuation.resume(with: result)
            }
        }
    }

    @available(iOS 13.0.0, *)
    @discardableResult
    func execute<Request: APIRequest>(_ request: Request) async throws -> (Data, HTTPURLResponse, HTTPStatusCode) {
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
}


public extension APIDispatcher {
    func dispatch<Request: APIDecodableRequest>(
        _ request: Request,
        completion: @escaping (Result<(Request.ResponseBodyType, HTTPURLResponse, HTTPStatusCode), Error>) -> ()) {
        do {
            let urlRequest = try request.urlRequest
            data(from: urlRequest) { [weak self] result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let response):
                    guard let self = self else { return }
                    guard let httpResponse = response.1 as? HTTPURLResponse else {
                        completion(.failure(APIError.invdalidHttpResponse))
                        return
                    }

                    guard let statusCode = HTTPStatusCode(rawValue: httpResponse.statusCode) else {
                        completion(.failure(APIError.couldNotCreateHTTPStatusCode))
                        return
                    }

                    do {
                        if request.failingStatusCodes.contains(statusCode) {
                            let decoded = try self.decoder.decode(Request.ErrorBodyType.self, from: response.0)
                            completion(.failure(decoded))
                        } else if request.successStatusCodes.contains(statusCode) {
                            let decoded = try self.decoder.decode(Request.ResponseBodyType.self, from: response.0)
                            completion(.success((decoded, httpResponse, statusCode)))
                        } else {
                            completion(.failure(APIError.statusCodeNotHandled))
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}
