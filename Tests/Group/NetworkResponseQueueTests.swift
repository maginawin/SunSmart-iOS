import Foundation

// Only the transport is doubled. Both callbacks and business/error mappings
// are extracted from NetworkRequest.swift by the runner.
extension String { var localizedString: String { self } }
enum NetowrkReqeustApi { case siteInfo; var diagnosticName: String { "siteInfo" } }
protocol Cancellable { func cancel() }
struct Token: Cancellable { func cancel() {} }
struct AFError: Error { let underlyingError: Error? }
enum MoyaError: Error {
    case underlying(Error, Response?)
    case statusCode(Response)
    var response: Response? {
        switch self {
        case .underlying(_, let value): return value
        case .statusCode(let value): return value
        }
    }
}
struct Response {
    let statusCode: Int
    let data: Data
    func mapJSON() throws -> Any {
        precondition(!Thread.isMainThread, "JSON parsing must leave the main thread")
        return try JSONSerialization.jsonObject(with: data)
    }
    func filter(statusCode: Int) throws -> Response {
        guard self.statusCode == statusCode else { throw MoyaError.statusCode(self) }
        return self
    }
}
final class TestProvider {
    var result: Result<Response, MoyaError>!
    func request(_ target: NetowrkReqeustApi, callbackQueue: DispatchQueue?,
                 completion: @escaping (Result<Response, MoyaError>) -> Void) -> Cancellable {
        guard let callbackQueue else { preconditionFailure("Missing response queue") }
        let result = result!
        callbackQueue.async { completion(result) }
        return Token()
    }
}

@main enum NetworkResponseQueueTests {
    static func main() {
        let request = NetworkRequest()
        let cases: [(String, Int, Bool)] = [
            (#"{"code":200,"data":{"nodes":[]}}"#, 200, true),
            (#"{"isSuccess":true}"#, 200, true),
            (#"{"code":4009,"message":"denied"}"#, 200, false),
            ("[1,2]", 200, false), ("invalid JSON", 200, false),
            (#"{"code":503}"#, 503, false)
        ]
        for (body, status, expected) in cases {
            request.provider.result = .success(.init(statusCode: status, data: Data(body.utf8)))
            run(request, expected: expected)
        }
        request.provider.result = .failure(.underlying(NSError(domain: NSURLErrorDomain, code: -1009), nil))
        run(request, expected: false)
        print("PASS: both production adapters parse off main, deliver success/failure on main, and preserve business/error outcomes")
    }

    static func run(_ request: NetworkRequest, expected: Bool) {
        var calls = 0
        func received(_ success: Bool) {
            precondition(Thread.isMainThread, "UI completion must return to main")
            precondition(success == expected)
            calls += 1
        }
        request.request(.siteInfo) { result in
            switch result {
            case .success: received(true)
            case .failure: received(false)
            }
        }
        request.request(.siteInfo, success: { _ in received(true) }, failure: { _ in received(false) })
        let deadline = Date().addingTimeInterval(3)
        while calls < 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(calls == 2, "Missing completion")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(calls == 2, "Duplicate completion")
    }
}
