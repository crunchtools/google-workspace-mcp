# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
