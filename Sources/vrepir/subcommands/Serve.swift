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

internal import ApplicationProtobuf
internal import ArgumentParser
internal import Foundation
internal import GRPCCore
internal import GRPCNIOTransportHTTP2
internal import HomomorphicEncryption
internal import PrivateInformationRetrieval

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run PIR test service")

    @Argument var databaseDir: String

    @Argument var params: String

    @Option var host: String = "192.168.64.1"

    @Option var port: UInt16 = 5555

    mutating func run() async throws {
        let params = try Apple_SwiftHomomorphicEncryption_Api_Pir_V1_SimplePIRConfig(from: params)
        // hint is unused on the server
        let hint = Array2d<UInt64>()
        let shardCount = params.hintIdentifiers.count
        let pirServers = try await withThrowingTaskGroup(of: (Int, SimplePirServer<UInt64>).self) { group in
            for index in 0..<shardCount {
                group.addTask { [databaseDir] in
                    let processedDatabase = try Array2d<UInt64>(from: "\(databaseDir)/pir-db-\(index).bin")
                    let server = try await SimplePirServer<UInt64>(
                        processedDatabase: processedDatabase,
                        hint: hint,
                        params: params.params[index].native())
                    return (index, server)
                }
            }

            var servers: [SimplePirServer<UInt64>?] = Array(repeating: nil, count: shardCount)
            for try await (index, server) in group {
                servers[index] = server
            }
            return servers.compactMap { $0 }
        }

        let service = EncryptedVisualSearchService(servers: pirServers)
        let server = GRPCServer(
            transport: .http2NIOPosix(address: .ipv4(host: host, port: Int(port)), transportSecurity: .plaintext),
            services: [service])

        try await withThrowingTaskGroup { group in
            group.addTask {
                try await server.serve()
            }

            if let address = try await server.listeningAddress {
                print("EncryptedVisualSearchService listening on \(address)")
            }
        }
    }
}
