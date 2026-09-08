import Foundation
import SwiftParser
import SwiftSyntax

final class Audit: SyntaxVisitor {
    let path: String
    var entries: [[String: Any]] = []

    init(path: String) {
        self.path = path
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let outputFunctions = [
            "print", "Swift.print", "debugPrint", "Swift.debugPrint",
            "NSLog", "os_log", "dump", "Swift.dump"
        ]
        guard outputFunctions.contains(node.calledExpression.trimmedDescription) else {
            return .visitChildren
        }
        var ancestor = node.parent
        var guarded = false
        while let current = ancestor {
            // 保守要求显式 DEBUG 分支；#else、注释和名称含 Debug 的方法不算保护。
            if let clause = current.as(IfConfigClauseSyntax.self),
               clause.condition?.trimmedDescription == "DEBUG" {
                guarded = true
            }
            ancestor = current.parent
        }
        entries.append([
            "path": path,
            "start": node.positionAfterSkippingLeadingTrivia.utf8Offset,
            "guarded": guarded
        ])
        return .visitChildren
    }
}
var entries: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let tree = Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8))
    precondition(!tree.hasError, "无法完整解析源码：\(path)")
    let audit = Audit(path: path)
    audit.walk(tree)
    entries += audit.entries
}
let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
