// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

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

import PackageDescription

let package = Package(
    name: "VREPIRService",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-homomorphic-encryption.git",
            revision: "68675885a9b1ca4229014ce50ce651c3f369b8c6"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "vrepir",
            dependencies: [
                .product(name: "ApplicationProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PrivateInformationRetrieval", package: "swift-homomorphic-encryption"),
                .product(name: "HomomorphicEncryptionProtobuf", package: "swift-homomorphic-encryption"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "MemoryMapping", package: "swift-homomorphic-encryption"),
            ],
            exclude: ["protobuf/proto"]),
    ])
