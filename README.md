# workflows

Collection of reusable GitHub Actions workflows:

* [Docker build, push and tag](#docker-build-push-and-tag)

## Docker build, push and tag
[Workflow file](.github/workflows/docker-build-tag-push.yaml)

Sets up docker and builds a container from `Dockerfile` in the calling repository.

The workflow authenticates to Google Container Registry through Workload Identity Federation. The calling repository needs to be given access to use workload identity. Ask #team-platform about this.

The workflow generates the following tags on the built container image:
- `latest` if the event was a push to the default branch of the repository.
- `commit-sha` (short) on push.
- `vx.y.z` for push events with semver tag.

### Example usage:
```yaml
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
