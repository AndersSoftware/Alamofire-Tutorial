import Alamofire

public class APIManager {
    public static let shared = APIManager()
    
    func execute(serverUrl: String, httpBody: Data?, method: HTTPMethod = .get, parameters: Parameters? = nil, success: @escaping ((AFDataResponse<String>) -> Void), failure: @escaping ((APIError) -> Void)) {
        guard let url = URL(string: serverUrl) else {
            failure(APIError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = 30
        
        AF.request(request, interceptor: Interceptor()).validate().responseString { response in
            switch response.result {
            case .success:
                success(response)
            case .failure(let error):
                let apiError = APIError.httpError(
                    statusCode: response.response?.statusCode ?? 0,
                    message: error.localizedDescription
                )
                failure(apiError)
            }
        }
    }
}

final class Interceptor: RequestInterceptor {
    
    private let attemptTracker = RequestAttemptTracker()

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequestToUse = urlRequest
        
        if let accessToken = KeychainHelper.standard.read(service: "accesstoken", account: "madplan"),
           let tokenString = String(data: accessToken, encoding: .utf8) {
            let cleanToken = tokenString.replacingOccurrences(of: "\"", with: "")
            urlRequestToUse.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }
        
        completion(.success(urlRequestToUse))
    }
    
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        let requestKey = "\(request.id)"
        
        Task {
            let currentAttempts = await attemptTracker.getAttempts(for: requestKey)
            
            if currentAttempts >= 3 {
                await attemptTracker.removeAttempts(for: requestKey)
                completion(.doNotRetry)
                return
            }
            
            if let response = request.task?.response as? HTTPURLResponse {
                switch response.statusCode {
                case 400...499:
                    await attemptTracker.removeAttempts(for: requestKey)
                    completion(.doNotRetryWithError(error))
                    return
                case 500...599:
                    await attemptTracker.incrementAttempts(for: requestKey)
                    completion(.retryWithDelay(3))
                    return
                default:
                    break
                }
            }
            
            await attemptTracker.incrementAttempts(for: requestKey)
            completion(.retryWithDelay(3))
        }
    }

}

actor RequestAttemptTracker {
    private var attempts: [String: Int] = [:]
    
    func getAttempts(for key: String) -> Int {
        attempts[key] ?? 0
    }
    
    func incrementAttempts(for key: String)  {
        let current = attempts[key] ?? 0
        let new = current + 1
        attempts[key] = new
    }
    
    func removeAttempts(for key: String) {
        attempts.removeValue(forKey: key)
    }
}

enum APIError: Error {
    case invalidURL
    case networkError(String)
    case httpError(statusCode: Int, message: String)
    case decodingError
    case noData
    case unauthorized
}
