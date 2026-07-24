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
internal import Foundation

struct Codebook {
    let centroids: [Embedding]

    func convert() throws -> Apple_SwiftHomomorphicEncryption_Pir_V1_EmbeddingCodebook {
        let embeddingDimension = centroids.first?.count ?? 0
        guard let embeddingDimensionField = UInt32(exactly: embeddingDimension) else {
            throw ProcessError.embeddingDimensionOutOfRange(dimension: embeddingDimension)
        }

        return .with { codebook in
            codebook.embeddingDimension = embeddingDimensionField

            var float16Embeddings = Data(capacity: centroids.count * embeddingDimension * MemoryLayout<Float16>.size)
            for centroid in centroids {
                for value in centroid {
                    let fp16 = Float16(value)
                    float16Embeddings.append(contentsOf: fp16.bitPattern.bigEndianBytes)
                }
            }
            codebook.centroidEmbeddingFp16 = float16Embeddings
        }
    }
}
