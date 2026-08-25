//
//  FetchService.swift
//  Loader
//
//  Created by samara on 14.03.2025.
//

import Foundation

// MARK: - Class
public class NBFetchService {
	
	public enum NBFetchServiceError: Error, LocalizedError {
		case invalidURL
		case networkError(Error)
		case noData
		case parsingError(Any)
		
		public var errorDescription: String? {
			switch self {
			case .invalidURL:
				return "The URL is invalid."
			case .networkError(let error):
				return "Network error: \(error.localizedDescription)"
			case .noData:
				return "No data received."
			case .parsingError(let error):
				return "Failed to parse data: \(error)"
			}
		}
	}
	
	public init() {}
	
	/// Extra headers to attach to a request, decided per URL by the host app.
	/// A closure keeps this package free of any one backend's details while
	/// still letting an app authenticate the fetches it owns.
	public nonisolated(unsafe) static var headerProvider: (@Sendable (URL) -> [String: String])?
}

// MARK: - Class extension: fetch
extension NBFetchService {
	public func fetch<T: Decodable>(
		from urlString: String,
		completion: @escaping (Result<T, Error>) -> Void
	) {
		guard let url = URL(string: urlString) else {
			completion(.failure(NBFetchServiceError.invalidURL))
			return
		}
		
		fetch(from: url, completion: completion)
	}
	
	public func fetch<T: Decodable>(
		from url: URL,
		completion: @escaping (Result<T, Error>) -> Void
	) {
		var request = URLRequest(url: url)
		
		for (field, value) in Self.headerProvider?(url) ?? [:] {
			request.setValue(value, forHTTPHeaderField: field)
		}
		
		DispatchQueue.global(qos: .userInitiated).async {
			let task = URLSession.shared.dataTask(with: request) { data, response, error in
				if let error = error {
					completion(.failure(NBFetchServiceError.networkError(error)))
					return
				}
				
				guard let data = data else {
					completion(.failure(NBFetchServiceError.noData))
					return
				}
				
				do {
					let decoder = JSONDecoder()
					let decodedData = try decoder.decode(T.self, from: data)
					completion(.success(decodedData))
				} catch let decodingError as DecodingError {
					if case .dataCorrupted(let context) = decodingError {
						
						if let underlyingError = context.underlyingError as NSError? {
							
                            if let debugDesc = underlyingError.userInfo["NSDebugDescription"] {
                                print(debugDesc)
                                completion(.failure(NBFetchServiceError.parsingError(debugDesc)))
                            } else {
                                print(decodingError)
                                completion(.failure(NBFetchServiceError.parsingError(decodingError)))
                            }
						}
					}
					
				} catch {
                    print(error)
					completion(.failure(NBFetchServiceError.parsingError(error)))
				}
			}
			
			task.resume()
		}
	}
}
