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
internal import GRPCCore
internal import GRPCProtobuf
internal import HomomorphicEncryption
internal import PrivateInformationRetrieval
internal import SwiftProtobuf

struct EncryptedVisualSearchService {
    let servers: [SimplePirServer<UInt64>]
}

extension EncryptedVisualSearchService: Apple_Parsec_Encryptedvisualsearch_V1_EncryptedVisualSearch
    .SimpleServiceProtocol
{
    func encryptedVisualSearch(
        request: Apple_Parsec_Encryptedvisualsearch_V1_EncryptedVisualSearchRequest,
        context _: GRPCCore
            .ServerContext) async throws -> Apple_Parsec_Encryptedvisualsearch_V1_EncryptedVisualSearchResponse
    {
        do {
            guard let firstRequest = request.queries.first else {
                throw RPCError(code: .invalidArgument, message: "Empty request")
            }

            let apiRequest = try Apple_SwiftHomomorphicEncryption_Api_V1_Request(unpackingAny: firstRequest
                .computeRequest)
            let simplePirRequest = apiRequest.simplePirRequest
            let shardIndex = Int(simplePirRequest.shardIndex)
            guard servers.indices.contains(shardIndex) else {
                print("invalid shard index \(shardIndex), have \(servers.count) shard(s)")
                throw RPCError(code: .invalidArgument, message: "Invalid shard index")
            }
            let server = servers[shardIndex]

            // Validate before native(): mismatched dimensions otherwise trip a precondition trap inside the
            // PIR library (Array2d.init, multiply) rather than throwing.
            let queryMatrix = simplePirRequest.request
            let queryRowCount = Int(queryMatrix.rowCount)
            let queryColumnCount = Int(queryMatrix.colCount)
            let (elementCount, overflow) = queryRowCount.multipliedReportingOverflow(by: queryColumnCount)
            guard !overflow,
                  elementCount == queryMatrix.data.count,
                  queryColumnCount == server.processedDatabase.shape.columnCount
            else {
                print("""
                    invalid query matrix: rowCount=\(queryRowCount) colCount=\(queryColumnCount) \
                    dataCount=\(queryMatrix.data.count) expectedColCount=\(server.processedDatabase.shape.columnCount)
                    """)
                throw RPCError(code: .invalidArgument, message: "Invalid query matrix dimensions")
            }

            let result = try await server.computeResponse(to: queryMatrix.native()).proto()
            let apiResult = Apple_SwiftHomomorphicEncryption_Api_V1_Response.with { response in
                response.simplePirResponse = .with { simplePirResponse in
                    simplePirResponse.response = result
                }
            }

            return try Apple_Parsec_Encryptedvisualsearch_V1_EncryptedVisualSearchResponse.with { response in
                response.results = try [
                    Apple_Parsec_Encryptedvisualsearch_V1_EVSResult.with { evsResult in
                        evsResult.computeResponse = try Google_Protobuf_Any(message: apiResult)
                    },
                ]
            }
        } catch {
            print("search error: \(error)")
            throw RPCError(code: .internalError, message: "\(error)")
        }
    }
}
