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

enum Clustering {
    struct ClusteringResult {
        let codebook: Codebook
        let clusters: [Cluster]
    }

    struct Cluster {
        let documents: [Document]
    }

    static func cluster(documents: [Document], codebookSize: Int) -> ClusteringResult {
        guard !documents.isEmpty else {
            return ClusteringResult(codebook: Codebook(centroids: []), clusters: [])
        }

        let k = min(codebookSize, documents.count)

        // Initialize centroids using k-means++ algorithm
        let initialCentroids = initializeCentroidsKMeansPlusPlus(documents: documents, k: k)

        // Cap iterations so we terminate even if k-means oscillates between equidistant assignments;
        // in practice the convergence check below exits far sooner.
        let maxIterations = 100
        var centroids = initialCentroids
        // Optional so the first pass can't false-converge against a placeholder all-zeros assignment.
        var assignments: [Int]?

        for _ in 0..<maxIterations {
            let newAssignments = documents.map { document in
                centroids.enumerated()
                    .map { index, centroid in
                        (index: index, similarity: document.embedding.cosineSimilarity(to: centroid))
                    }
                    .max { $0.similarity < $1.similarity }?
                    .index ?? 0
            }

            guard newAssignments != assignments else {
                break
            }
            assignments = newAssignments

            centroids = (0..<k).map { clusterIndex in
                let clusterEmbeddings = zip(documents, newAssignments)
                    .filter { _, assignment in assignment == clusterIndex }
                    .map(\.0.embedding)

                return clusterEmbeddings.isEmpty
                    ? centroids[clusterIndex]
                    : clusterEmbeddings.mean()
            }
        }

        let finalCentroids = centroids
        let finalAssignments = assignments ?? Array(repeating: 0, count: documents.count)

        // Build clusters from final assignments
        let clusters = (0..<k).map { clusterIndex in
            let clusterDocuments = zip(documents, finalAssignments)
                .filter { _, assignment in assignment == clusterIndex }
                .map(\.0)
            return Cluster(documents: clusterDocuments)
        }

        let codebook = Codebook(centroids: finalCentroids)

        return ClusteringResult(codebook: codebook, clusters: clusters)
    }

    // MARK: - Helper Methods

    private static func initializeCentroidsKMeansPlusPlus(documents: [Document], k: Int) -> [Embedding] {
        // Ensure k doesn't exceed document count
        guard !documents.isEmpty, k > 0 else {
            return []
        }

        let clampedK = min(k, documents.count)

        // Choose first centroid randomly
        guard let firstIndex = documents.indices.randomElement() else {
            return []
        }

        var centroids = [documents[firstIndex].embedding]
        var selectedIndices = Set<Int>([firstIndex])

        // Choose remaining centroids using k-means++ algorithm
        for _ in 1..<clampedK {
            let distances = documents.enumerated().map { index, document in
                // If already selected, set distance to 0 (won't be selected again)
                guard !selectedIndices.contains(index) else {
                    return Float(0)
                }

                let maxSimilarity = centroids
                    .map { document.embedding.cosineSimilarity(to: $0) }
                    .max() ?? 0
                let distance = 1 - maxSimilarity
                return distance * distance
            }

            let totalDistance = distances.reduce(0, +)

            // Handle edge case where all documents are already selected
            guard totalDistance > 0 else {
                break
            }

            let selectedIndex = selectWeightedRandomIndex(weights: distances)

            selectedIndices.insert(selectedIndex)
            centroids.append(documents[selectedIndex].embedding)
        }

        return centroids
    }

    private static func selectWeightedRandomIndex(weights: [Float]) -> Int {
        let totalWeight = weights.reduce(0, +)
        let random = Float.random(in: 0..<totalWeight)

        var cumulative: Float = 0
        return weights.indices.first { index in
            cumulative += weights[index]
            return cumulative >= random
        } ?? 0
    }
}
