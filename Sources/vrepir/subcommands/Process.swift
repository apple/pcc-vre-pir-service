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
internal import MemoryMapping

struct Process: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Process raw database")

    @Argument var input: String

    @Argument var indexType: IndexType

    @Option var codebookSize: Int = 10

    @Argument var output: String

    mutating func run() async throws {
        let inputData = try Data(contentsOf: URL(filePath: input))
        let documents = try JSONDecoder().decode([Document].self, from: inputData)
        print("Loaded \(documents.count) documents")

        let clusteringResult = Clustering.cluster(documents: documents, codebookSize: codebookSize)

        let keywordDatabase = try Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabase.with { keywordDB in
            keywordDB.rows = try clusteringResult.clusters.enumerated().map { clusterIndex, cluster in
                try .with { row in
                    row.keyword = Data("\(clusterIndex)".utf8)
                    row.value = try cluster.aspireResult(indexType: indexType).serializedData()
                }
            }
        }

        let keywordDatabasePath = "\(output)/database.binpb"
        let codebookPath = "\(output)/embedding_codebook.binpb"
        let assetMetadataPath = "\(output)/asset_metadata.bin"
        let bigClustersPath = "\(output)/big_clusters.bin"
        try keywordDatabase.save(to: keywordDatabasePath)
        try clusteringResult.codebook.convert().save(to: codebookPath)

        var assetMetadataBuilder = MMapDictionary.Builder()
        for document in documents {
            let metadata = try document.assetMetadata().serializedData()
            let key = indexType == .book ? "\(document.id)" : "Q\(document.id)"
            assetMetadataBuilder.insert(key: key, value: Array(metadata))
        }

        try assetMetadataBuilder.write(to: assetMetadataPath)

        let bigClustersBuilder = MMapDictionary.Builder()
        try bigClustersBuilder.write(to: bigClustersPath)
    }
}
