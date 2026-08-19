// Copyright 2026 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

internal import Foundation

/// The `SimplePIRProcessDatabase` configuration file. `vrepir process` writes it next to the database
/// it produced, so the shard count and paths can't drift from the artifacts they describe. Property
/// names are the JSON keys `SimplePIRProcessDatabase` decodes, so don't rename them.
struct SimplePirProcessingConfig: Codable {
    let inputDatabase: String
    let outputDatabasePrefix: String
    let latticeDimension: Int
    let errorStdDev: Double
    let plaintextModulusBits: Int
    let ciphertextModulusBits: Int
    let shardCount: Int

    init(
        inputDatabase: String,
        outputDatabasePrefix: String,
        shardCount: Int,
        latticeDimension: Int = 2048,
        errorStdDev: Double = 6.4,
        plaintextModulusBits: Int = 14,
        ciphertextModulusBits: Int = 42)
    {
        self.inputDatabase = inputDatabase
        self.outputDatabasePrefix = outputDatabasePrefix
        self.latticeDimension = latticeDimension
        self.errorStdDev = errorStdDev
        self.plaintextModulusBits = plaintextModulusBits
        self.ciphertextModulusBits = ciphertextModulusBits
        self.shardCount = shardCount
    }

    func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: URL(filePath: path))
    }
}
