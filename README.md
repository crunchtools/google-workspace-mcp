# crunchtools/google-workspace-mcp

Google Workspace MCP server (Gmail, Calendar, Drive, Docs, Sheets, Slides) —
the crunchtools deployment of upstream
[taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
packaged under the crunchtools container image profile.

Sister to the rest of the [crunchtools/mcp-*](https://github.com/crunchtools)
fleet. Speaks streamable HTTP, so it's reachable both by container-network DNS
and, for a client running outside the container network, by whatever port
forwarding or tunnel that deployment sets up.

## Build

```bash
podman build -t quay.io/crunchtools/google-workspace-mcp .
```

The image is multi-stage Hummingbird Python 3.13: builder pulls + installs
upstream at a pinned tag, runtime ships only the venv + source tree + Python.
No build tools, no package manager, no shell.

## Run

Running more than one instance — e.g. separate Google accounts or workspaces
— just means separate containers with separate OAuth credentials and data
dirs; nothing in the image assumes there's only one.

```bash
podman run -d --name google-workspace-personal --rm \
  --network crunchtools \
  -p 127.0.0.1:8011:8000 \
  -v /path/to/google-workspace-personal/data:/app/data:Z \
  --env-file /path/to/google-workspace-personal/config/google-workspace-personal.env \
  quay.io/crunchtools/google-workspace-mcp
```

Bind to `127.0.0.1` only — never public — and reach it from outside the
container network however that deployment reaches other local MCP servers
(SSH tunnel, gateway, etc; a client on the same container network can just
use container DNS, e.g. `http://google-workspace-personal:8000/mcp`). Which
tools/instances a given agent can reach is the deployment's decision, not
something this image enforces.

## Composition

- Base: `quay.io/hummingbird/python:3.13` (per the crunchtools image profile)
- Upstream: `taylorwilsdon/google_workspace_mcp` at `v${WORKSPACE_MCP_VERSION}` (build arg, default tracks the latest tested upstream tag)
- Multi-stage build; runtime carries no build tools, no shell, no package manager
- Streamable HTTP transport — same protocol the rest of the crunchtools MCP fleet speaks
- HEALTHCHECK probes the upstream's `/health` endpoint

## Configuration

The upstream's full config matrix is documented at
[workspacemcp.com](https://workspacemcp.com/). The env file passed via
`--env-file` typically contains the Google OAuth client ID + secret + scope
set; the OAuth refresh token lives in the bind-mounted data dir at
`/app/data/credentials.json`.

OAuth refresh tokens are bound to the OAuth *application* (client ID), not the
host, so copying an existing token to a new host works without re-consent —
same client, same scopes.

## Why no `schedule:` trigger

Per the org-wide cascade cleanup (see
[crunchtools/constitution / `validate-cascade.py`](https://github.com/crunchtools/constitution)),
no crunchtools workflow has a `schedule:` trigger. Weekly rebuilds are
pulsed by Hermes via `workflow_dispatch` and `repository_dispatch`; CVE
pickup happens on the parent-image-updated dispatch fanout from the
Hummingbird python:3.13 image.

## License

This repo is MIT-licensed (matches upstream). The container image bundles
upstream source code at the pinned tag; upstream is also MIT-licensed.
