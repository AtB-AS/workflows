# workflows

Collection of reusable GitHub Actions workflows:

* [Docker Build, Push & Deploy](#docker-build-push--deploy)
* [Docker build & Push](#docker-build--push)

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
    branches: ['main']

jobs:
  build:
    uses: atb-as/workflows/.github/workflows/cluster-docker-build-tag-push.yaml@main
    with:
      application: amp
      image: gcr.io/atb-mobility-platform/foo
      instance_id: foo
    secrets:
      github_pat: ${{ secrets.GH_PAT }}
```

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

## Docker Build & Push

[Workflow file](.github/workflows/docker-build-tag-push.yaml)

Sets up docker and builds a container from `Dockerfile` in the calling repository.

The workflow authenticates to Google Container Registry through Workload Identity Federation. The calling repository needs to be given access to use workload identity. Ask #team-platform about this.

The workflow generates the following tags on the built container image:

- `latest` if the event was a push to the default branch of the repository.
- `commit-sha` (short) on push.
- `vx.y.z` for push events with semver tag.

### Example usage

```yaml
name: Docker Build & Push

on:
  push:
    tags:
      - v*
    branches:
      - main

jobs:
  build:
    uses: atb-as/workflows/.github/workflows/docker-build-push.yaml@main
    with:
      image: gcr.io/atb-mobility-platform/foo
      build_args: |
        FOO=BAR
      secrets: |
        PASSWORD=shh
```
