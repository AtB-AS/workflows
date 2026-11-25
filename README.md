# workflows

Collection of reusable GitHub Actions workflows:

- [Docker Build, Push & Deploy](#docker-build-push--deploy)
- [Rust](#rust)

## Rust

[Workflow file](.github/workflows/rust.yaml)

Runs the standard checks for a Rust repository:

- **Format**: `cargo fmt --all -- --check` (nightly by default, since the shared rustfmt config uses `group_imports`).
- **Clippy**: `cargo clippy --locked --workspace --all-targets --all-features -- -D warnings`.
- **Test**: `cargo test --locked --workspace`.
- **Audit**: `cargo audit` against `Cargo.lock`.

### Example usage

```yaml
name: Rust

on:
  workflow_dispatch:
  push:
    branches: ["main"]
  pull_request:

jobs:
  rust:
    uses: atb-as/workflows/.github/workflows/rust.yaml@v2
    with:
      toolchain: "1.100"
      protoc: true
    secrets:
      github_pat: ${{ secrets.GH_PAT }}
```

### Inputs

| Input           | Default                                    | Description                                                                                             |
| --------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `toolchain`     | `""`                                       | Toolchain for clippy and test. Empty uses `rust-toolchain.toml` in the calling repo, otherwise stable.  |
| `fmt_toolchain` | `nightly`                                  | Toolchain for `cargo fmt`.                                                                              |
| `protoc`        | `false`                                    | Install `protoc` (needed when a dependency compiles `.proto` files, e.g. `entur-proto`).                |
| `deny_warnings` | `true`                                     | Fail clippy on warnings. Only turn off temporarily while cleaning up a repo.                            |
| `clippy_args`   | `--workspace --all-targets --all-features` | Arguments passed to `cargo clippy`.                                                                     |
| `test_args`     | `--workspace`                              | Arguments passed to `cargo test`.                                                                       |
| `audit`         | `true`                                     | Run `cargo audit`.                                                                                      |

### Toolchain

CI and the Docker image should build with the same compiler. Either pass `toolchain` with the
same version as the `FROM rust:<version>` builder image in the Dockerfile, or commit a
`rust-toolchain.toml` and leave `toolchain` empty.

### Private git dependencies

`github_pat` is only needed when the repository depends on private git repositories. The token
is given to git through the environment of the cargo step only. It is never written to
`~/.gitconfig`, so it does not end up in a cache. Dependencies must use the
`ssh://git@github.com/...` URL form.

## Docker Build, Push & Deploy

[Workflow file](.github/workflows/cluster-docker-build-tag-push.yaml)

Sets up docker and builds a container from `Dockerfile` in the calling repository.

The workflow authenticates to Google Container Registry through Workload Identity Federation. The calling repository needs to be given access to use workload identity. Ask #team-platform about this.

The workflow generates the following tags on the built container image:

- `latest` if the event was a push to the default branch of the repository.
- `commit-sha` (short) on push.
- `vx.y.z` for releases with semver tag.

### Example usage

```yaml
name: Docker Build, Push & Deploy

on:
  release:
    types: [published]
  push:
    branches: ["main"]

jobs:
  build:
    uses: atb-as/workflows/.github/workflows/cluster-docker-build-tag-push.yaml@v2

    with:
      image: gcr.io/atb-mobility-platform/foo
    secrets:
      github_pat: ${{ secrets.GH_PAT }}
```

### Building a migrations image alongside the app image

If your service applies database migrations (e.g. a [Flyway](https://documentation.red-gate.com/flyway)
image run as an ArgoCD PreSync hook), set `migrations_dockerfile` to build a **second image in
the same run**. Both images are built before anything is deployed, so if either build fails the
whole run fails and **neither** image is bumped — and on success both image tags are bumped in
the same infra commit (one ArgoCD sync), keeping the app and its migrations atomic.

```yaml
jobs:
  build:
    uses: atb-as/workflows/.github/workflows/cluster-docker-build-tag-push.yaml@v2
    with:
      image: gcr.io/atb-mobility-platform/foo
      migrations_dockerfile: Dockerfile.migrations
    secrets:
      github_pat: ${{ secrets.GH_PAT }}
```

The migrations image is named `<image>-migrations` by default (e.g.
`gcr.io/atb-mobility-platform/foo-migrations`); override with `migrations_image`. It is tagged
the same way as the app image (short SHA on push, semver on release). Omit
`migrations_dockerfile` and the workflow behaves exactly as before (single image).

### Deploy to staging (normal PR flow)

1. Create PR
2. Get approval
3. Merge into main branch
4. The docker image is built and tagged
5. The docker image is pushed to GCR
6. The docker image is deployed to staging

### Deploy to production

1. Create a GitHub release with a tag
2. The docker image is built and tagged (skipped if it exists)
3. The docker image is pushed to GCR (skipped if it exists)
4. The docker image is deployed to production

### Deploy a hotfix to production

Only do this if there are changes in main that cannot be deployed to production.

1. Checkout the tag and create a new branch
2. Make the hotfix and push the branch
3. Create a new release from the branch
4. The docker image is built and tagged (skipped if it exists)
5. The docker image is pushed to GCR (skipped if it exists)
6. The docker image is deployed to production

### Rolling back a release

It's preferable to do this as a PR in the `cluster-infra` repo. Do a revert of the commit that deployed the release you want to roll back and create a PR with the reverted commit.
