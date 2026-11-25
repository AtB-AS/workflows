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

`clippy_args` and `test_args` are split on whitespace. Use quotes to keep a value with spaces
together (`--features "one two"`). They are not evaluated by a shell, so globs and variables
are passed to cargo as written.

### Toolchain

CI and the Docker image should build with the same compiler. Either pass `toolchain` with the
same version as the `FROM rust:<version>` builder image in the Dockerfile, or commit a
`rust-toolchain.toml` and leave `toolchain` empty.

### Private git dependencies

`github_pat` is only needed when the repository depends on private git repositories. The token
only needs read access to those repositories. Dependencies must use the
`ssh://git@github.com/...` URL form.

How the token is handled:

- It is used by one step, `cargo fetch --locked`, and passed to git through the environment of
  that step. It is never written to `~/.gitconfig`.
- Clippy and the tests then run offline. The token is not in their environment, in git
  configuration or on disk, so build scripts, procedural macros and test code do not see it by
  reading those. This is not a barrier against code that deliberately attacks the runner, so
  keep the token read-only and limited to the repositories that are needed.
- The build cache holds the sources of the private dependencies. It is only saved when the
  calling repository is private (or no token was given), because in a public repository a pull
  request from a fork can read the caches of the base branch.

### Pull requests from forks and from Dependabot

GitHub does not pass the repository's Actions secrets to workflows triggered by a pull request
from a fork, or by a pull request from Dependabot. In a repository with private git
dependencies, Clippy and Test cannot fetch them and fail for such pull requests. Format and
Audit still work.

- **Dependabot**: add the token as a Dependabot secret with the same name (repository or
  organisation settings, _Secrets and variables_, _Dependabot_). Dependabot pull requests then
  get it.
- **Forks**: to skip the workflow for fork pull requests instead of failing:

  ```yaml
  jobs:
    rust:
      if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
      uses: atb-as/workflows/.github/workflows/rust.yaml@v2
  ```

### Shared setup action

The jobs share their setup (toolchain, protoc, cache, dependency download) through the
composite action [`setup-rust`](.github/actions/setup-rust/action.yml). The workflow refers to
it as `atb-as/workflows/.github/actions/setup-rust@v2`, because a reusable workflow cannot
refer to its own repository with a relative path. The workflow and the action are therefore
released together by moving the `v2` tag. To test a branch, point the three references in
`rust.yaml` at that branch while testing.

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
