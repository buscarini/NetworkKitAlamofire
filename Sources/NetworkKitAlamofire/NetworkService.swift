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
	
	@discardableResult
	static func alamofireRequest(_ sessionConfig: URLSessionConfiguration) -> (
		URL,
		NetworkKit.Request<Data>,
		@escaping NetworkService.Log,
		@escaping NetworkService.Progress,
		@escaping (NetworkKit.NetworkResponse<Data?>) -> Void
		) -> NetworkService.CancelRequest {
			return { baseUrl, request, log, progress, completion in
				let totalUrl = request.fullUrl(baseUrl: baseUrl)
				
				var components = URLComponents(url: totalUrl, resolvingAgainstBaseURL: false)
				components?.queryItems = request.extraQueryItems
				let finalUrl = components?.url ?? totalUrl
				
				switch request.type {
				case .request(let parameters, let parametersEncoding):
					return self.request(
						sessionConfig: sessionConfig,
						url: finalUrl,
						method: request.method,
						headers: request.headers,
						parameters: parameters,
						parametersEncoding: parametersEncoding,
						successCodes: request.successCodes,
						log: log,
						progress: progress,
						completion: completion)
					
				case .uploadMultipartData(let parameters):
					return uploadMultipart(
						sessionConfig: sessionConfig,
						url: finalUrl,
						method: request.method,
						headers: request.headers,
						parameters: parameters,
						successCodes: request.successCodes,
						log: log,
						progress: progress,
						completion: completion
					)
				}
			}
	}
	
	private static func request(
		sessionConfig: URLSessionConfiguration,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: [String: String]?,
		parameters: [String: Any]?,
		parametersEncoding: ParametersEncoding,
		successCodes: Range<Int>,
		log: @escaping NetworkService.Log,
		progress: @escaping NetworkService.Progress,
		completion: @escaping (NetworkKit.NetworkResponse<Data?>) -> Void
		) -> NetworkService.CancelRequest {
		let encodingAlamofire = parametersEncoding.alamofire
		let methodAlamofire = method.alamofire
		let successCodesArray = Array(successCodes.lowerBound ..< successCodes.upperBound)
		
		let manager = SessionManager(configuration: sessionConfig)
		
		let dataRequest = manager
			.request(
				url,
				method: methodAlamofire,
				parameters: parameters,
				encoding: encodingAlamofire,
				headers: headers)
		
		log(dataRequest.debugDescription)
		
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
			})
		
		return dataRequest.cancel
	}
	
	private static func uploadMultipart(
		sessionConfig: URLSessionConfiguration,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: [String: String]?,
		parameters: [String: MultipartParameter],
		successCodes: Range<Int>,
		log: @escaping NetworkService.Log,
		progress: @escaping NetworkService.Progress,
		completion: @escaping (NetworkKit.NetworkResponse<Data?>) -> Void
		) -> NetworkService.CancelRequest {
		
		let methodAlamofire = method.alamofire
		
		let manager = SessionManager(configuration: sessionConfig)
		
		manager
			.upload(multipartFormData: { formData in
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
					to: url,
					method: methodAlamofire,
					headers: headers,
					encodingCompletion: { encodingResult in
						switch encodingResult {
						case .success(let request, _, _):
							
							log(request.debugDescription)
							
							request
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
