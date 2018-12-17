import Foundation

import NetworkKit
import Alamofire

public extension NetworkService {
	public static func alamofire(_ baseUrl: URL) -> NetworkService {
		return NetworkService.init(baseUrl: baseUrl, request: self.alamofireRequest)
	}
	
    @discardableResult
    public static func alamofireRequest(
		_ baseUrl: URL,
    	_ request: NetworkKit.Request<Data>,
    	log: @escaping NetworkService.Log,
    	progress: @escaping NetworkService.Progress,
    	completion: @escaping (NetworkKit.NetworkResponse<Data?>) -> Void
	) -> NetworkService.CancelRequest {
        
        let finalUrl = request.fullUrl(baseUrl: baseUrl)
        
        switch request.type {
        case .request(let parameters, let parametersEncoding):
            return self.request(
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
    
    private static func request(
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
        
        let dataRequest = Alamofire
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
                
            })
        
        return dataRequest.cancel
    }
    
    private static func uploadMultipart(
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
        
        Alamofire
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
                            }
                            
                        case .failure(let error):
                            completion(.encodingError(error))
                            return
                        }
            })
        
        return {} // TODO: See how to cancel multipart requests
        
    }
}
