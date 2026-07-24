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

internal import ArgumentParser
internal import Foundation
internal import SwiftProtobuf

enum IndexType: String, CaseIterable, ExpressibleByArgument {
    case animal
    case art
    case book
    case landmark
    case pet
}

extension Document {
    func rankingSignal(indexType: IndexType) throws -> Aspiresnippetpb_EmbeddingSnippet.OneOf_RankingSignals {
        switch indexType {
        case .art:
            try .artSignals(.with { $0.kgEntityID = try knowledgeGraphEntityID() })
        case .book:
            try .bookSignals(.with { $0.bookAdamID = try bookAdamID() })
        case .animal:
            try .animalSignals(.with { $0.kgEntityID = try knowledgeGraphEntityID() })
        case .landmark:
            try .landmarkSignals(.with { $0.kgEntityID = try knowledgeGraphEntityID() })
        case .pet:
            try .petSignals(.with { $0.kgEntityID = try knowledgeGraphEntityID() })
        }
    }

    /// `id` comes from operator-supplied JSON, so validate the narrowing rather than trapping on a bad value.
    private func knowledgeGraphEntityID() throws -> UInt32 {
        guard let value = UInt32(exactly: id) else {
            throw ProcessError.identifierOutOfRange(id: id, field: "kgEntityID")
        }
        return value
    }

    private func bookAdamID() throws -> UInt64 {
        guard let value = UInt64(exactly: id) else {
            throw ProcessError.identifierOutOfRange(id: id, field: "bookAdamID")
        }
        return value
    }

    func assetMetadata() -> Aspireresultpb_AspireResult {
        .with { result in
            result.assetMetadata = .with { metadata in
                metadata.privateVlu = .with { vluMetadata in
                    vluMetadata.localizedTitle = localizedTitles
                }
            }
        }
    }
}

extension Clustering.Cluster {
    func aspireResult(indexType: IndexType) throws -> Aspireresultpb_AspireResult {
        try .with { result in
            result.embeddingCluster = try .with { embeddingCluster in
                embeddingCluster.embeddingSnippet = try documents.map { document in
                    try .with { embeddingSnippet in
                        embeddingSnippet.embeddingFp16 = document.embedding.fp16Data()
                        embeddingSnippet.rankingSignals = try document.rankingSignal(indexType: indexType)
                    }
                }
            }
        }
    }
}
