import Foundation

import NetworkKit
import Alamofire

public extension NetworkService {
	private static var lastManager: SessionManager?
	
	static var defaultConfig: URLSessionConfiguration {
		let configuration = URLSessionConfiguration.default
		configuration.httpAdditionalHeaders = SessionManager.defaultHTTPHeaders
		return configuration
	}
	
	static func alamofire(_ baseUrl: URL, _ sessionConfig: URLSessionConfiguration = NetworkService.defaultConfig) -> NetworkService {
		return NetworkService.init(baseUrl: baseUrl, request: self.alamofireRequest(sessionConfig))
	}
	
	static func alamofire(_ baseUrl: URL, _ manager: SessionManager) -> NetworkService {
		return NetworkService.init(baseUrl: baseUrl, request: self.alamofireRequest(manager))
	}
	
	@discardableResult
	static func alamofireRequest(_ sessionConfig: URLSessionConfiguration) -> (
		URL,
		NetworkKit.Request<Data>,
		@escaping NetworkService.Log,
		@escaping NetworkService.Progress,
		@escaping (NetworkKit.NetworkResponse<Data?>) -> Void
		) -> NetworkService.CancelRequest {
			let manager = SessionManager(configuration: sessionConfig)
			return alamofireRequest(manager)
	}
	
	@discardableResult
	static func alamofireRequest(_ manager: SessionManager) -> (
		URL,
		NetworkKit.Request<Data>,
		@escaping NetworkService.Log,
		@escaping NetworkService.Progress,
		@escaping (NetworkKit.NetworkResponse<Data?>) -> Void
		) -> NetworkService.CancelRequest {
			return { baseUrl, request, log, progress, completion in
				let totalUrl = request.fullUrl(baseUrl: baseUrl)
				
				let finalUrl: URL
				if request.extraQueryItems.count > 0 {
					// WARN: This method unescapes url query parameters in the original full url, and then escapes it again. This can cause issues with some characters depending on the server implementation. For example, Azure escapes / and + while iOS won't
					var components = URLComponents(url: totalUrl, resolvingAgainstBaseURL: false)
					let queryItems = (components?.queryItems ?? []) + request.extraQueryItems
					components?.queryItems = queryItems
					finalUrl = components?.url ?? totalUrl
				}
				else {
					finalUrl = totalUrl
				}
				
				switch request.type {
				case .request(let parameters, let parametersEncoding):
					return self.request(
						manager: manager,
						url: finalUrl,
						method: request.method,
						headers: request.headers,
						parameters: parameters,
						parametersEncoding: parametersEncoding,
						successCodes: request.successCodes,
						cachePolicy: request.cachePolicy,
						log: log,
						progress: progress,
						completion: completion
					)
					
				case .uploadMultipartData(let parameters):
					return uploadMultipart(
						manager: manager,
						url: finalUrl,
						method: request.method,
						headers: request.headers,
						parameters: parameters,
						successCodes: request.successCodes,
						cachePolicy: request.cachePolicy,
						log: log,
						progress: progress,
						completion: completion
					)
				}
			}
	}
	
	private static func request(
		manager: SessionManager,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: [String: String]?,
		parameters: [String: Any]?,
		parametersEncoding: ParametersEncoding,
		successCodes: Range<Int>,
		cachePolicy: URLRequest.CachePolicy,
		log: @escaping NetworkService.Log,
		progress: @escaping NetworkService.Progress,
		completion: @escaping (NetworkKit.NetworkResponse<Data?>) -> Void
	) -> NetworkService.CancelRequest {
		let encodingAlamofire = parametersEncoding.alamofire
		let methodAlamofire = method.alamofire
		let successCodesArray = Array(successCodes.lowerBound ..< successCodes.upperBound)
		
		
		let dataRequest: DataRequest
		do {
			var originalRequest = try URLRequest(url: url, method: methodAlamofire, headers: headers)
			originalRequest.cachePolicy = cachePolicy
			let encodedURLRequest = try encodingAlamofire.encode(originalRequest, with: parameters)
			dataRequest = manager.request(encodedURLRequest)
		} catch let error {
			completion(.encodingError(error))
			return {}
		}
		
		//
		//		let dataRequest = manager
		//			.request(
		//				url,
		//				method: methodAlamofire,
		//				parameters: parameters,
		//				encoding: encodingAlamofire,
		//				headers: headers
		//			)
		
		log("⬆️ \(dataRequest.debugDescription)")
		
		dataRequest
			.validate(statusCode: successCodesArray)
			.downloadProgress(closure: { requestProgress in
				progress(requestProgress.completedUnitCount, requestProgress.totalUnitCount)
			})
			.response(completionHandler: { response in
				
				let responseHTTP = response.response
				let data = response.data
				let error = response.error
				
				let statusCode = responseHTTP?.statusCode ?? 9999
				
				let response = HTTPResponse(responseCode: statusCode, data: data, url: responseHTTP?.url ?? url, headerFields: responseHTTP?.allHeaderFields as? [String: String] ?? [:] )
				
				log("📩 \(response.debugDescription)")
				
				if let error = error {
					let responseError = ResponseError.network(error)
					completion(.networkError(responseError, response))
					return
				}
				
				let finalResponse = NetworkResponse.success(data, response)
				completion(finalResponse)
				
				// Trick to keep the manager alive until the end
				self.lastManager = manager
			})
		
		return dataRequest.cancel
	}
	
	private static func uploadMultipart(
		manager: SessionManager,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: [String: String]?,
		parameters: [String: MultipartParameter],
		successCodes: Range<Int>,
		cachePolicy: URLRequest.CachePolicy,
		log: @escaping NetworkService.Log,
		progress: @escaping NetworkService.Progress,
		completion: @escaping (NetworkKit.NetworkResponse<Data?>) -> Void
	) -> NetworkService.CancelRequest {
		
		let methodAlamofire = method.alamofire
		
		let successCodesArray = Array(successCodes.lowerBound ..< successCodes.upperBound)
		
		let urlRequest: URLRequest
		do {
			urlRequest = try URLRequest(url: url, method: methodAlamofire, headers: headers)
		}
		catch let error {
			completion(.encodingError(error))
			return {}
		}
		
		
//		return upload(
//			multipartFormData: multipartFormData,
//			usingThreshold: encodingMemoryThreshold,
//			with: urlRequest,
//			queue: queue,
//			encodingCompletion: encodingCompletion
//		)
		
		manager
			.upload(
				multipartFormData: { formData in
					for (name, parameter) in parameters {
						let data: Data = parameter.data
						guard let fileParameter = parameter.fileParameter else {
							formData.append(data, withName: name)
							continue
						}
						if let fileName = fileParameter.fileName {
							let stream = InputStream(data: data)
							let length = UInt64(data.count)
							formData.append(stream, withLength: length, name: name, fileName: fileName, mimeType: fileParameter.mimeType)
						} else {
							formData.append(data, withName: name, mimeType: fileParameter.mimeType)
						}
					}
				},
				usingThreshold: SessionManager.multipartFormDataEncodingMemoryThreshold,
				with: urlRequest,
				encodingCompletion: { encodingResult in
					switch encodingResult {
					case .success(let request, _, _):
						
						log(request.debugDescription)
						
						//							request.request?.cachePolicy = cachePolicy
						
						request
							.validate(statusCode: successCodesArray)
							.uploadProgress(closure: { requestProgress in
								progress(requestProgress.completedUnitCount, requestProgress.totalUnitCount)
							})
							.response { response in
								
								let responseHTTP = response.response
								let data = response.data
								let error = response.error
								
								let statusCode = responseHTTP?.statusCode ?? 9999
								let response = HTTPResponse(responseCode: statusCode, data: data, url: responseHTTP?.url ?? url, headerFields: responseHTTP?.allHeaderFields as? [String: String] ?? [:] )
								
								log(response.debugDescription)
								
								if let error = error {
									let responseError = ResponseError.network(error)
									completion(.networkError(responseError, response))
									return
								}
								
								let finalResponse = NetworkResponse.success(data, response)
								completion(finalResponse)
								
								// Trick to keep the manager alive until the end
								self.lastManager = manager
						}
						
					case .failure(let error):
						completion(.encodingError(error))
						// Trick to keep the manager alive until the end
						self.lastManager = manager
						return
					}
			})
		
		return {} // TODO: See how to cancel multipart requests
	}
}
