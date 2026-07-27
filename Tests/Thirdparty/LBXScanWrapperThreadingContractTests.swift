import Foundation

@main
struct LBXScanWrapperThreadingContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected the LBXScanWrapper.swift path")
        }

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )

        require(
            source.contains("private let sessionQueue = DispatchQueue("),
            "LBXScanWrapper must own a dedicated serial session queue"
        )
        require(
            !source.contains("DispatchQueue.global"),
            "LBXScanWrapper must not use the global concurrent queue for session lifecycle"
        )

        let startBody = try methodBody(named: "start", in: source)
        requireLifecycleOperation(
            "session.startRunning()",
            in: startBody,
            methodName: "start"
        )

        let stopBody = try methodBody(named: "stop", in: source)
        requireLifecycleOperation(
            "session.stopRunning()",
            in: stopBody,
            methodName: "stop"
        )

        print("LBXScanWrapperThreadingContractTests passed")
    }

    private static func methodBody(
        named name: String,
        in source: String
    ) throws -> Substring {
        let signature = "func \(name)()"
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else {
            throw ContractError.missingMethod(name)
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw ContractError.unterminatedMethod(name)
    }

    private static func requireLifecycleOperation(
        _ operation: String,
        in methodBody: Substring,
        methodName: String
    ) {
        guard let queueRange = methodBody.range(of: "sessionQueue.async"),
              let runningRange = methodBody.range(of: "session.isRunning"),
              let operationRange = methodBody.range(of: operation) else {
            preconditionFailure(
                "\(methodName) must check session state and execute \(operation) on sessionQueue"
            )
        }

        require(
            queueRange.lowerBound < runningRange.lowerBound,
            "\(methodName) must read isRunning inside sessionQueue"
        )
        require(
            runningRange.lowerBound < operationRange.lowerBound,
            "\(methodName) must check isRunning before \(operation)"
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }

    private enum ContractError: Error {
        case missingMethod(String)
        case unterminatedMethod(String)
    }
}
