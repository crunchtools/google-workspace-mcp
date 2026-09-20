# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.3] - 2026-09-20

### Security

- Added `.trivyignore` for GHSA-6v7p-g79w-8964 (msgpack 1.1.2) and
  CVE-2025-47273 (setuptools 70.3.0). v1.0.2 removed pip from this repo's own
  venv, but the same two CVEs are also baked into the runtime base image
  itself (`quay.io/hummingbird/python:3.13`'s own vendored pip at
  `/usr/local/lib/python3.13/site-packages`), which this repo does not build
  and cannot patch -- the runtime stage is distroless with no shell to strip
  it. Confirmed unreachable: not on PATH, never invoked, no lazy install or
  package-index call anywhere in this image. Accepted by Scott (2026-09-20);
  see `.trivyignore` for the full justification. Revisit if Hummingbird ships
  a base image without the stale vendored pip.

## [1.0.2] - 2026-09-20

### Security

- v1.0.1's msgpack/setuptools bump didn't actually close the Trivy gate: the
  vulnerable versions Trivy flagged (msgpack 1.1.2, setuptools 70.3.0) were
  never the top-level packages -- they're pip's OWN internally vendored
  copies (`pip/_vendor`, pinned in `pip/_vendor/vendor.txt`), frozen inside
  pip 26.2 itself and untouched by `pip install --upgrade`. Confirmed by
  building the image locally and inspecting the venv directly. Since this
  image never runs pip at runtime (the venv is built once in the builder
  stage; the runtime stage only execs main.py), the fix is to strip pip out
  of the shipped venv entirely -- removing the vulnerable code rather than
  papering over the finding, and incidentally fixing an actual violation of
  this Containerfile's own "no build tools in the runtime image" intent.
  Verified: no `pip` package, dist-info, or `_vendor` tree remains anywhere
  in the built image; the app's own msgpack (1.2.2) and setuptools (84.0.0)
  still import cleanly; `main.py` still parses.

## [1.0.1] - 2026-09-20

### Security

- Bumped `msgpack` 1.1.2 -> 1.2.1+ (GHSA-6v7p-g79w-8964, HIGH: out-of-bounds
  read/crash on Unpacker reuse after an error) and `setuptools` 70.3.0 ->
  78.1.1+ (CVE-2025-47273, HIGH: path traversal in PackageIndex). Neither
  is a direct dependency pinned by this repo -- upstream's pyproject.toml
  only requires `setuptools>=61.0` and doesn't pin msgpack at all, so pip
  resolved older transitive versions at build time. Force-upgraded both
  post-install in the Containerfile; upstream's loose constraints don't
  fight the resolver. Verified: image builds clean, both packages report
  the new versions at runtime, and `main.py` still imports without error.

## [1.0.0] - 2026-09-20

First tagged release. This image has been running in production since
before it had version control; this release marks the current state as
the baseline going forward.
