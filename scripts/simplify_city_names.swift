import Foundation

// Build-time name normalization only. Input/output are ordered JSON string arrays.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
let converted = names.map { $0.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? $0 }
FileHandle.standardOutput.write(try JSONEncoder().encode(converted))
