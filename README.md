# VREPIRService

A test server for exercising Private Information Retrieval (PIR) and Visual Lookup
(VLU) inside the Private Cloud Compute (PCC) Virtual Research Environment (VRE).

## Overview

Visual Lookup lets users identify visual entities — art, books, animals,
landmarks, and pets — in an image. The device generates an embedding of the
image locally, and PCC compares that embedding against a large database of
known entities on the device's behalf. That database is too large to ship to
the device, and it lives outside the PCC trust boundary, so VLU retrieves
from it using PIR: the database server does not learn which cluster a query
targets.

**VREPIRService is the server side of that retrieval path, packaged for the VRE.**
It plays the role of the external PIR server: it builds a clustered,
PIR-ready database from raw entity data, serves encrypted queries against that
database over gRPC, and packages the accompanying assets into a cryptex that a
PCC instance mounts. We built it so you can stand up and inspect the end-to-end
VLU flow on a research machine, without production infrastructure.

The service is deliberately minimal. It is a research and testing tool, not a
production component, and it does not by itself provide PCC's security
guarantees; those come from the PIR protocol it speaks and the VRE it runs in.

## How Visual Lookup uses this service

The device does not send the raw image. It computes an embedding locally and
sends that embedding into PCC, where a sequence of delegated components
resolves the query against the entity database without revealing which
cluster the query targets to this service:

1. **On device**: The device generates the image embedding; the raw image
   does not leave it. The device sends the embedding to `VLUAgent`, a PCC
   Agent workflow running on a proxy node.
2. **Delegation to a worker node**: `VLUAgent` makes a *delegated tool call*,
   handing the embedding to a `PCCAgentWorkerApp` instance running on a
   separate PCC node.
3. **Cluster selection**: `PCCAgentWorkerApp` forwards the embedding to its
   `cb_jobhelper` process, which uses the *embedding codebook* to find the
   cluster centroid nearest the embedding. `cb_jobhelper` uses the embedding
   only within the PCC trust boundary; the result identifies the cluster most
   likely to contain a match, turning a full-database lookup into a single
   PIR query.
4. **Encrypted query**: `cb_jobhelper` issues an encrypted PIR query for that
   cluster's index and sends it to this service.
5. **Server computation**: VREPIRService runs the homomorphic PIR computation
   over the processed database shard and returns an encrypted response.
   VREPIRService does not learn which cluster the request targets or the
   contents of the response it computes.
6. **Re-ranking and response**: `cb_jobhelper` decrypts the response and
   returns the cluster to `PCCAgentWorkerApp`, which returns it to
   `VLUAgent`. `VLUAgent` re-ranks the entities in the cluster against the
   embedding, resolves the winning entries to human-readable metadata such as
   localized titles, and returns the results to the device.

## Architecture

VREPIRService is a single command-line tool, `vrepir`, with two subcommands,
plus one processing tool sourced from `swift-homomorphic-encryption`.

- **`vrepir process`**: Turns raw entity documents (embeddings plus metadata)
  into a clustered database. It runs k-means clustering to build an embedding
  codebook of cluster centroids, groups documents into clusters, and emits the
  cluster contents, the codebook, a per-entity asset-metadata table, the stash
  of oversized clusters, and the `SimplePIRProcessDatabase` configuration.
- **`vrepir serve`**: Loads the processed PIR database shards and answers
  `EncryptedVisualSearch` gRPC requests. Each request carries a SimplePIR query
  targeting a shard; the server computes the homomorphic response and returns it.
  It also answers the `EncryptedVisualSearchConfig` RPC that `cb_bridged` calls
  on an interval to hold its connection open, and logs a line per request.
- **`SimplePIRProcessDatabase`** (from `swift-homomorphic-encryption`):
  Transforms the clustered database into PIR-ready shards and hints.

### Data artifacts

The pipeline produces a small set of files that together make up a deployable
VLU index:

| Artifact | Produced by | Purpose |
|----------|-------------|---------|
| `database.binpb` | `vrepir process` | Clustered entity database (one keyword-database row per cluster) |
| `embedding_codebook.binpb` | `vrepir process` | Cluster centroids `cb_jobhelper` uses for cluster selection |
| `asset_metadata.bin` | `vrepir process` | Per-entity metadata (for example, localized titles) for resolving the winning entries |
| `big_clusters.bin` | `vrepir process` | Clusters serializing larger than `--max-cluster-size`, served outside the PIR database; empty unless that option is set |
| `config.json` | `vrepir process` | `SimplePIRProcessDatabase` configuration, including the shard count from `--shards` |
| `pir-db-*.bin`, `pir-db-*.hint.bin` | `SimplePIRProcessDatabase` | PIR database shards and their hints |
| `pir-db.config.binpb` | `SimplePIRProcessDatabase` | PIR parameters shared by this service and `cb_jobhelper` |

### Cloud asset distribution

In production, PCC delivers the codebook, stash, and PIR configuration to PCC
nodes as cloud assets instead of baking them into node images. The
`cloudassetdownloaderd` daemon listens for asset-information updates from the
PCC control plane, downloads the specified assets, and extracts them to the
node's file system. `cloudboardd` subscribes to updates for the assets
`cb_jobhelper` and its paired application require; when
`cloudassetdownloaderd` notifies it of a new asset set, `cloudboardd`
relaunches `cb_jobhelper` and the paired application and prewarms them with
the new assets. Each asset's hash is recorded in the request execution log,
so a request's asset dependencies stay auditable.

The VRE doesn't run `cloudassetdownloaderd`. VREPIRService substitutes a
cryptex for cloud asset distribution: in [Getting started](#getting-started),
you package `asset_metadata.bin`, `big_clusters.bin`,
`embedding_codebook.binpb`, `pir-db-*.hint.bin`, and `pir-db.config.binpb` into
a cryptex and add it to the `pcc-agent-worker` instance directly, rather than
publishing them for `cloudassetdownloaderd` to fetch.

## The database pipeline

Building an index is a two-stage transformation from raw documents to a
PIR-ready database:

1. **Cluster and encode:** `vrepir process` reads a JSON array of documents —
   each an embedding, an id, and localized titles — and clusters them. The
   result is a keyword database keyed by cluster id, where each value is the
   serialized set of embeddings and ranking signals for that cluster. It also
   writes the codebook, the asset-metadata table, and the
   `SimplePIRProcessDatabase` configuration. Clusters serializing larger than
   `--max-cluster-size` (for example `2KiB`) go to the stash instead, keeping
   their cluster index so the remaining indices stay aligned with the codebook
   centroids. Because the PIR chunk size follows the largest database entry,
   stashing a few outsized clusters keeps every hint and query small.
2. **Process for PIR:** `SimplePIRProcessDatabase` consumes the clustered
   database and produces the SimplePIR shards, hints, and configuration. It also
   verifies that a retrieved value round-trips correctly before you use the
   database.

The supported index types are `animal`, `art`, `book`, `landmark`, and `pet`.

## Privacy model

The property that matters is the one PIR provides: **PIR is designed so that
this service does not learn which cluster a query targets, and so does not
reveal the contents of the device's embedding.** `cb_jobhelper` selects the
cluster inside the PCC trust boundary using the codebook; the query that
reaches this service is encrypted, and the homomorphic computation produces
an encrypted response without decrypting the query. The device transmits
only embeddings, and only through PCC and PIR; it does not send raw images.

This repository is a test harness. In the VRE it stands in for the external
PIR server so you can exercise and audit the retrieval path; it is not
itself hardened for production use.

## Protocol buffers

The gRPC service and message schemas live under
`Sources/vrepir/protobuf/proto`, and the generated Swift lives in
`Sources/vrepir/protobuf/generated`. We vendor only the `.proto` files this
service defines or consumes and that a dependency doesn't already provide:

- `serving/proto/parsec/encryptedvisualsearch/v1`: The `EncryptedVisualSearch`
  gRPC service and its request and response messages
- `serving/proto/aspireresultpb` and `serving/proto/aspiresnippetpb`: The
  cluster payload (`AspireResult`, `EmbeddingClusterSnippet`,
  `AssetMetadataSnippet`)
- `serving/proto/parsec/search`: Shared status and error types

We consume PIR and codebook types (for example, `EmbeddingCodebook`,
`KeywordDatabase`, and the SimplePIR request and response messages) directly from
`swift-homomorphic-encryption`, so we don't vendor them here.

To regenerate the Swift sources after editing a `.proto`, run
`Utilities/UpdateGeneratedProtobuf.sh`. It requires `protoc`,
`protoc-gen-swift`, and `protoc-gen-grpc-swift-2` on your `PATH`, wipes the
`generated` directory, and regenerates from the vendored protos.

## Requirements

- An Apple-Silicon Mac able to run the PCC Virtual Research Environment. The
  `pccvre` tool ships at `/System/Library/SecurityResearch/usr/bin`.
- macOS 26 or newer with a matching Swift 6.2 toolchain (the package declares
  `swift-tools-version: 6.2` and a `.macOS(.v26)` platform).
- To regenerate the protobuf sources (only if you edit a `.proto`): `protoc`,
  `protoc-gen-swift`, and `protoc-gen-grpc-swift-2` on your `PATH`.

## Getting started

The following walks through building a VLU index, deploying it to a VRE
instance, and issuing a request.

First, put `pccvre` on your path:

```sh
echo "/System/Library/SecurityResearch/usr/bin" | sudo tee /etc/paths.d/20-vre
```

Second, make sure that you agree to the license, which can be done by running `pccvre` using sudo.
On first launch it will display the license.
```sh
sudo pccvre
```

This service needs two releases from the transparency log: a **PCC Agent**
release for the `pcc-agent` instance, and a **PCC Agent Worker** release for
the `pcc-agent-worker` instance. Transparency-log release indices are not
stable identifiers — new builds are published continuously and old ones age
out of `pccvre`'s downloadable set — so any index pinned in this README would
be out of date by the time you read it. Look up the current downloadable
index for each application name instead:

```sh
pccvre release list --json --count 40 \
  | jq -r '.[] | select(.downloadable and
      (.applicationName == "PCC Agent" or .applicationName == "PCC Agent Worker")) |
      "\(.index)\t\(.applicationName)\t\(.buildVersion)"' \
  | sort -rn
```

Take the highest (newest) index listed for each application name and export them:

```sh
export PCC_AGENT_RELEASE=<newest PCC Agent index from above>
export PCC_AGENT_WORKER_RELEASE=<newest PCC Agent Worker index from above>
```

`vre-configuration.json.example` ships with placeholder `release` fields. Fill
in the indices you just found and write the result to `vre-configuration.json`
before running `pccvre workload create`:

```sh
jq --arg a "$PCC_AGENT_RELEASE" --arg w "$PCC_AGENT_WORKER_RELEASE" \
  '.instances |= map(.release = {"pcc-agent": $a, "pcc-agent-worker": $w}[.name])' \
  vre-configuration.json.example > vre-configuration.json
```

Download releases, configure instances, build the tools, process an index,
and package the assets:

```sh
# Download PCC releases
pccvre release download --release "$PCC_AGENT_RELEASE"
pccvre release download --release "$PCC_AGENT_WORKER_RELEASE"
# Configure the instances
pccvre workload create --configuration vre-configuration.json
# build executables
swift build -c release --product vrepir
swift build -c release --product SimplePIRProcessDatabase
# Process input into clusters
mkdir output
./.build/release/vrepir process input.json art output
# Process database
./.build/release/SimplePIRProcessDatabase output/config.json
# copy assets and create a cryptex out of them
mkdir -p CipherMLAssets/encryptedVluArt
cp output/{asset_metadata.bin,big_clusters.bin,embedding_codebook.binpb,pir-db-*.hint.bin,pir-db.config.binpb} CipherMLAssets/encryptedVluArt
pccvre cryptex create --source CipherMLAssets --variant CipherMLAssets --mount-point /private/var/CipherMLAssets
# add cryptex to PCC Agent Worker
pccvre instance configure cryptex add -N pcc-agent-worker -C CipherMLAssets:CipherMLAssets.aar
# enable ssh (optional)
pccvre instance configure ssh --name pcc-agent -p ~/.ssh/id_ecdsa.pub
pccvre instance configure ssh --name pcc-agent-worker -p ~/.ssh/id_ecdsa.pub
```

Start the instances:

```sh
# start the instances
pccvre instance start --name pcc-agent --name pcc-agent-worker
```

Note that it takes some time for the instances to boot and be ready to accept requests.

Start the test PIR service (`serve` takes the processed-database directory and
the PIR config; `--host` should match your VRE bridge address):

```sh
# start the test PIR service
./.build/release/vrepir serve output output/pir-db.config.binpb --host 192.168.64.1
```

Make a VLU request through the trusted proxy:

```sh
pccvre instance invoke --name pcc-agent tie-vre-cli \
  --payload '{"echo_agent_request": { "msg": "{\"index\":\"encryptedVluArt\", \"embedding\": [0, 1, 0]}" }}' \
  --tie-proxy pcc-agent.local \
  --hostname pcc-agent-worker.local \
  --workload-parameters '{"inference-id": ["com.apple.fm.service.vlu.v1"]}' \
  --parse-as-generate-request false \
  --request-bypass false
```

## Troubleshooting

### Double-check the IP address

List the running instances and note their IP addresses:

```sh
pccvre instance list
```

If an address falls in the 192.168.64.X range, the virtual bridge interface uses
the 192.168.64.X subnet, so your host uses 192.168.64.1. Update the IP address in
`vre-configuration.json` if needed, and set a matching `--host` value on the
`vrepir serve` command.

After you edit `vre-configuration.json`, overwrite the existing configuration:

```sh
pccvre workload create --configuration vre-configuration.json --force
```

### SSH

If you enabled SSH:

```sh
# ssh into the worker:
ssh pcc-agent-worker.local
# once in, there is very limited functionality available
# disable shell-builtin log
disable log
# stream logs
log stream --info --predicate 'c:cloudos'
# stream CipherMLSE logs
log stream --info --predicate 'c:ciphermlse'
```

## Useful links

[PCC VRE overview](https://security.apple.com/documentation/private-cloud-compute/virtualresearchenvironment)

[Visual Lookup](https://security.apple.com/documentation/private-cloud-compute/visuallookup)

[Private Information Retrieval](https://security.apple.com/documentation/private-cloud-compute/pir)

[Runtime Configuration and Assets](https://security.apple.com/documentation/private-cloud-compute/runtimeconfigassets)

[Swift Homomorphic Encryption](https://github.com/apple/swift-homomorphic-encryption)
