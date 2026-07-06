# Release

Release Please opens release PRs and creates GitHub releases from commits on
`main` that change installable files only:

- `lfg.*`
- `functions/**`
- `completions/**`

The first release starts at `0.1.0`. Release PRs update `CHANGELOG.md`, the
Release Please manifest, and release-version annotations in the installable
shell files. Those annotations keep release PR merges inside the same path
filter, which allows Release Please to tag and publish the GitHub release after
the release PR is merged.

Release bumps are based on Conventional Commits:

- `fix:` creates a patch release.
- `feat:` creates a minor release.
- Breaking changes create a major release.

When a GitHub release is created, the workflow runs `scripts/release.sh` with
the released version and uploads `dist/lfg-<version>.tar.gz` to that release.
It also updates a `latest` tag/release and uploads `dist/lfg-latest.tar.gz`
there, so the remote installer can install the latest release without querying
the GitHub API.
