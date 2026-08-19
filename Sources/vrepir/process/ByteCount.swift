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

/// A size in bytes, written on the command line either bare (`2048`) or with a unit suffix
/// (`2KiB`, `1MB`). Suffixes are case-insensitive; binary units are powers of 1024 and decimal
/// units powers of 1000.
struct ByteCount: Equatable {
    /// Longest suffixes first, so `KiB` is matched before the bare `B` that also ends it. Stored in
    /// canonical casing for error messages; matching lowercases both sides.
    private static let unitMultipliers: [(suffix: String, multiplier: Int)] = [
        ("KiB", 1024),
        ("MiB", 1_048_576),
        ("GiB", 1_073_741_824),
        ("KB", 1000),
        ("MB", 1_000_000),
        ("GB", 1_000_000_000),
        ("B", 1),
    ]

    let bytes: Int
}

extension ByteCount {
    /// `ExpressibleByArgument` can only fail with nil, which throws away the reason; this initializer
    /// is wired up with `@Option(transform:)` instead so a bad value can say what was wrong with it.
    init(argument: String) throws {
        let normalized = argument.filter { !$0.isWhitespace }.lowercased()
        guard !normalized.isEmpty else {
            throw ValidationError("Expected a size in bytes, for example 2048 or 2KiB, but got an empty value")
        }

        let suffixMatch = Self.unitMultipliers.first { normalized.hasSuffix($0.suffix.lowercased()) }
        let digits = normalized.dropLast(suffixMatch?.suffix.count ?? 0)
        guard let value = Int(digits) else {
            throw ValidationError("""
                '\(argument)' is not a whole number of bytes; expected digits optionally followed by \
                \(Self.unitMultipliers.map(\.suffix).joined(separator: ", "))
                """)
        }
        guard value >= 0 else {
            throw ValidationError("A size cannot be negative, got '\(argument)'")
        }
        let (product, overflow) = value.multipliedReportingOverflow(by: suffixMatch?.multiplier ?? 1)
        guard !overflow else {
            throw ValidationError("'\(argument)' is too large to express as a number of bytes")
        }
        self.init(bytes: product)
    }
}

extension ByteCount: CustomStringConvertible {
    var description: String {
        "\(bytes) byte\(bytes == 1 ? "" : "s")"
    }
}
