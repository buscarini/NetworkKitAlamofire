import Foundation

import NetworkKit
import Alamofire

public extension NetworkService {
	private static var lastSession: Session?
	
	static var defaultConfig: URLSessionConfiguration {
		URLSessionConfiguration.af.default
	}
	
	static func alamofire(_ baseUrl: URL, _ sessionConfig: URLSessionConfiguration = NetworkService.defaultConfig) -> NetworkService {
		NetworkService.init(baseUrl: baseUrl, request: self.alamofireRequest(sessionConfig))
	}
	
	static func alamofire(_ baseUrl: URL, _ session: Session) -> NetworkService {
		NetworkService.init(baseUrl: baseUrl, request: self.alamofireRequest(session))
	}
	
	@discardableResult
	static func alamofireRequest(_ sessionConfig: URLSessionConfiguration) -> (
		URL,
		NetworkKit.Request<Data>,
		@escaping NetworkService.Log,
		@escaping NetworkService.Progress,
		@escaping (NetworkKit.NetworkResponse<Data?>) -> Void
	) -> NetworkService.CancelRequest {
		let manager = Session(configuration: sessionConfig)
		return alamofireRequest(manager)
	}
	
	@discardableResult
	static func alamofireRequest(_ session: Session) -> (
		URL,
		NetworkKit.Request<Data>,
		@escaping NetworkService.Log,
		@escaping NetworkService.Progress,
		@escaping (NetworkKit.NetworkResponse<Data?>) -> Void
	) -> NetworkService.CancelRequest {
		return { baseUrl, request, log, progress, completion in
			let totalUrl = request.fullUrl(baseUrl: baseUrl)
			
			let finalUrl: URL
			if request.queryItems.count > 0 {
				// WARN: This method unescapes url query parameters in the original full url, and then escapes it again. This can cause issues with some characters depending on the server implementation. For example, Azure escapes / and + while iOS won't
				var components = URLComponents(url: totalUrl, resolvingAgainstBaseURL: false)
				let queryItems = (components?.queryItems ?? []) + request.queryItems
				components?.queryItems = queryItems
				finalUrl = components?.url ?? totalUrl
			}
			else {
				finalUrl = totalUrl
			}
			
			let httpHeaders = request.headers.map(HTTPHeaders.init) ?? HTTPHeaders()
			
			switch request.type {
			case .request(let parameters, let parametersEncoding):
				return self.request(
					session: session,
					url: finalUrl,
					method: request.method,
					headers: httpHeaders,
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
					session: session,
					url: finalUrl,
					method: request.method,
					headers: httpHeaders,
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
		session: Session,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: HTTPHeaders,
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
			dataRequest = session.request(encodedURLRequest)
		} catch let error {
			completion(.encodingError(error))
			return {}
		}
		
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
				
				if let request = response.request {
					log("⬆️ \(request)")
				}

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
				//				self.lastManager = manager
			})
		
		return { dataRequest.cancel() }
	}
	
	private static func uploadMultipart(
		session: Session,
		url: URL,
		method: NetworkKit.HTTPMethod,
		headers: HTTPHeaders?,
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
		
		let uploadRequest = session
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
				with: urlRequest
			)
			.validate(statusCode: successCodesArray)
			.uploadProgress(closure: { requestProgress in
				progress(requestProgress.completedUnitCount, requestProgress.totalUnitCount)
			})
			.response { response in
				
				let responseHTTP = response.response
				let data = response.data
				let error = response.error
				
				if let request = response.request {
					log("⬆️ \(request)")
				}
				
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
//				self.lastManager = manager
			}
		
		return {
			uploadRequest.cancel()
		}
		
		/*		encodingCompletion: { encodingResult in
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
		})*/
		
		//		return {} // TODO: See how to cancel multipart requests
	}
}
