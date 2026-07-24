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

typealias Embedding = [Float]

// MARK: - Embedding Operations

extension Embedding {
    func normalized() -> Embedding {
        let magnitude = map { $0 * $0 }.reduce(0, +).squareRoot()
        return magnitude > 0 ? map { $0 / magnitude } : self
    }

    func fp16Data() -> Data {
        var data = Data(capacity: count * MemoryLayout<UInt16>.size)

        for value in self {
            let uint16 = UInt16(value.bitPattern >> 16)
            data.append(contentsOf: uint16.littleEndianBytes)
        }
        return data
    }

    func cosineSimilarity(to other: Embedding) -> Float {
        // Assumes both embeddings are normalized, so cosine similarity reduces to the dot product.
        zip(self, other)
            .map { $0 * $1 }
            .reduce(0, +)
    }
}

// MARK: - Array of Embeddings Operations

extension [Embedding] {
    func mean() -> Embedding {
        guard !isEmpty else {
            return []
        }

        guard let firstEmbedding = first else {
            return []
        }

        let dimension = firstEmbedding.count
        let count = Float(self.count)

        // Calculate element-wise sum across all embeddings
        let sum = reduce(into: [Float](repeating: 0, count: dimension)) { partialSum, embedding in
            for (index, value) in embedding.enumerated() {
                partialSum[index] += value
            }
        }

        // Calculate mean and normalize in one pass
        let meanEmbedding = sum.map { $0 / count }
        return meanEmbedding.normalized()
    }
}
