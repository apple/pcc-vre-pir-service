#!/usr/bin/env zsh

## Copyright 2026 Apple Inc. and the Swift Homomorphic Encryption project authors
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

set -e

# Regenerates the Swift protobuf / gRPC sources in
# Sources/vrepir/protobuf/generated from the .proto sources vendored under
# Sources/vrepir/protobuf/proto. This script has no external dependency: every
# .proto in the import closure (except the google/protobuf/* well-known types,
# which ship with protoc) lives in this repo.

protoc_swift_plugin="$(which protoc-gen-swift)"
protoc_grpc_plugin="$(which protoc-gen-grpc-swift-2)"
repo_root="$(git rev-parse --show-toplevel)"
proto_dir="${repo_root}/Sources/vrepir/protobuf/proto"
output_dir="${repo_root}/Sources/vrepir/protobuf/generated"

# Wipe the output dir up front so renamed or dropped protos don't leave stale
# generated files behind. NOTE: if any protoc call below fails (set -e),
# generated/ is left partially populated until the script is re-run
# successfully.
rm -rf "${output_dir}"
mkdir -p "${output_dir}"

# generate encryptedvisualsearch gRPC service (server only)
protoc \
  --proto_path=${proto_dir} \
  --plugin=protoc-gen-grpc-swift=${protoc_grpc_plugin} \
  --grpc-swift_out=${output_dir} \
  --grpc-swift_opt=Client=false \
  --grpc-swift_opt=Server=true \
  --grpc-swift_opt=FileNaming=PathToUnderscores \
  --grpc-swift_opt=UseAccessLevelOnImports=True \
  ${proto_dir}/serving/proto/parsec/encryptedvisualsearch/v1/encryptedvisualsearch_service.proto

# generate all message types in the import closure
#
# google/protobuf/*.proto well-known types are resolved from protoc's bundled
# include path, so they are not vendored or listed as generation targets.
protoc \
  --proto_path=${proto_dir} \
  --plugin=${protoc_swift_plugin} \
  --swift_out=${output_dir} \
  --swift_opt=UseAccessLevelOnImports=true \
  --swift_opt=FileNaming=PathToUnderscores \
  ${proto_dir}/serving/proto/parsec/encryptedvisualsearch/v1/encryptedvisualsearch_api.proto \
  ${proto_dir}/serving/proto/parsec/search/response_status.proto \
  ${proto_dir}/serving/proto/aspireresultpb/aspireresult.proto \
  ${proto_dir}/serving/proto/aspiresnippetpb/embedding_cluster_snippet.proto \
  ${proto_dir}/serving/proto/aspiresnippetpb/asset_metadata_snippet.proto
