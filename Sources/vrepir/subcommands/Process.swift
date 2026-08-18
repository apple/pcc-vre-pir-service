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

    @Option(
        help: ArgumentHelp(
            """
            Clusters serializing larger than this are written to the stash instead of the PIR \
            database, so a few outsized clusters can't inflate every hint and query. Accepts a unit \
            suffix, for example 2KiB; a bare number is bytes.
            """,
            valueName: "size"),
        transform: { try ByteCount(argument: $0) })
    var maxClusterSize: ByteCount?

    @Option(help: "Number of PIR shards to configure.")
    var shards: Int = 1

    @Argument var output: String

    func validate() throws {
        guard shards >= 1 else {
            throw ValidationError("'shards' must be at least 1, got \(shards)")
        }
    }

    mutating func run() async throws {
        let inputData = try Data(contentsOf: URL(filePath: input))
        let documents = try JSONDecoder().decode([Document].self, from: inputData)
        print("Loaded \(documents.count) documents")

        let clusteringResult = Clustering.cluster(documents: documents, codebookSize: codebookSize)

        // The PIR chunk size is derived from the largest database entry, so a few outsized clusters
        // would inflate every hint and query; the stash keeps them out of the PIR database entirely.
        // Stashed clusters keep their index, because the client looks the stash up by the same
        // codebook centroid index it would have queried PIR with.
        var databaseRows: [Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabaseRow] = []
        var bigClustersBuilder = MMapDictionary.Builder()
        var largestRetainedSize = 0
        var retainedDocumentCount = 0
        var smallestStashedSize = Int.max
        for (clusterIndex, cluster) in clusteringResult.clusters.enumerated() {
            let value = try cluster.aspireResult(indexType: indexType).serializedData()
            let keyword = "\(clusterIndex)"
            if let maxClusterSize, value.count > maxClusterSize.bytes {
                // Skip empty clusters: raising the threshold to their size wouldn't retain anything
                // retrievable, so they'd be misleading to report back.
                if !cluster.documents.isEmpty {
                    smallestStashedSize = min(smallestStashedSize, value.count)
                }
                bigClustersBuilder.insert(key: keyword, value: Array(value))
            } else {
                largestRetainedSize = max(largestRetainedSize, value.count)
                retainedDocumentCount += cluster.documents.count
                databaseRows.append(.with { row in
                    row.keyword = Data(keyword.utf8)
                    row.value = value
                })
            }
        }

        // k-means can leave empty clusters, which serialize to a couple of bytes and hold nothing to
        // retrieve, so count documents rather than rows or bytes to decide whether the PIR database
        // can still serve anything. Report the size the threshold would have to reach for this
        // dataset rather than guessing a lower bound when parsing the option.
        if let maxClusterSize, retainedDocumentCount == 0, smallestStashedSize < .max {
            throw ProcessError.allClustersStashed(
                maxClusterSize: maxClusterSize,
                smallestClusterSize: ByteCount(bytes: smallestStashedSize))
        }

        print("Stashed \(clusteringResult.clusters.count - databaseRows.count) of "
            + "\(clusteringResult.clusters.count) cluster(s), largest retained cluster is "
            + "\(largestRetainedSize) bytes")

        let keywordDatabase = Apple_SwiftHomomorphicEncryption_Pir_V1_KeywordDatabase.with { keywordDB in
            keywordDB.rows = databaseRows
        }

        let keywordDatabasePath = "\(output)/database.binpb"
        let codebookPath = "\(output)/embedding_codebook.binpb"
        let assetMetadataPath = "\(output)/asset_metadata.bin"
        let bigClustersPath = "\(output)/big_clusters.bin"
        let processingConfigPath = "\(output)/config.json"
        try keywordDatabase.save(to: keywordDatabasePath)
        try clusteringResult.codebook.convert().save(to: codebookPath)

        var assetMetadataBuilder = MMapDictionary.Builder()
        for document in documents {
            let metadata = try document.assetMetadata().serializedData()
            let key = indexType == .book ? "\(document.id)" : "Q\(document.id)"
            assetMetadataBuilder.insert(key: key, value: Array(metadata))
        }

        try assetMetadataBuilder.write(to: assetMetadataPath)
        try bigClustersBuilder.write(to: bigClustersPath)

        try SimplePirProcessingConfig(
            inputDatabase: keywordDatabasePath,
            outputDatabasePrefix: "\(output)/pir-db",
            shardCount: shards).save(to: processingConfigPath)
    }
}
