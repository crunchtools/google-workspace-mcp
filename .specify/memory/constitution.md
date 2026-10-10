# google-workspace-mcp Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.22.0
> **Profile:** Forked MCP Server

This file holds what is specific to google-workspace-mcp. The fleet rules and
the Forked MCP Server profile apply at the inherited version and are checked
against this repo's files by `constitution.yml`. They are not restated here.

## Upstream

- **Source:** https://github.com/taylorwilsdon/google_workspace_mcp
- **License:** MIT
- **Forked at:** v1.21.2 (`WORKSPACE_MCP_VERSION` build arg in the Containerfile)

This is a packaging repo, not a source fork: the builder stage clones
upstream at the pinned tag, so the repo holds only the Containerfile, the
workflows and this file. Moving to a new upstream release is a change to the
build arg.

## Deployment

- **Port:** 8011 on 127.0.0.1 for the personal instance (container port 8000)
- **Env file:** /srv/google-workspace-personal.crunchtools.com/config/google-workspace-personal.env
- **Credentials:** GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET; the
  OAuth refresh token lives in the bind-mounted data dir at
  `/app/data/credentials.json`, never in the image

One image serves several instances (separate Google accounts), each with its
own container, env file, data dir and port. Which agents can reach which
instance is the deployment's decision, not the image's.

## Patches

None to upstream code. The Containerfile changes how it is packaged:

- Multi-stage build on `quay.io/hummingbird/python:3.13-builder` /
  `quay.io/hummingbird/python:3.13`; upstream's `main.py` runs directly from
  the copied source tree because upstream has no PyPI entry point.
- `msgpack>=1.2.1` and `setuptools>=78.1.1` are forced after install
  (GHSA-6v7p-g79w-8964, CVE-2025-47273), and pip is removed from the shipped
  venv.
- HEALTHCHECK probes upstream's `/health` endpoint.

## Deviations

- **Image name and registries.** The image is
  `quay.io/crunchtools/google-workspace-mcp`, not `mcp-<name>`, and
  `build.yml` also pushes `ghcr.io/crunchtools/google-workspace-mcp`. Both
  predate the profile; renaming would break running deployments.
- **Accepted CVEs.** `.trivyignore` accepts GHSA-6v7p-g79w-8964 and
  CVE-2025-47273 in pip's vendored copies inside the Hummingbird base image,
  which this repo cannot patch and which nothing in the image invokes.
  Accepted by Scott on 2026-09-20; drop the entries when Hummingbird ships a
  base image without the stale vendored pip.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-10-02 | Initial manifest under constitution v1.18.0 |
