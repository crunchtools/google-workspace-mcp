# crunchtools/google-workspace-mcp

Google Workspace MCP server (Gmail, Calendar, Drive, Docs, Sheets, Slides) —
the crunchtools deployment of upstream
[taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
packaged under the crunchtools container image profile.

Sister to the rest of the [crunchtools/mcp-*](https://github.com/crunchtools)
fleet centralized on lotor. Consumed by Josui (Claude Code) via the SSH
forward tunnel and by Kagetora (Hermes) via the `crunchtools` podman network.

## Build

```bash
podman build -t quay.io/crunchtools/google-workspace-mcp .
```

The image is multi-stage Hummingbird Python 3.13: builder pulls + installs
upstream at a pinned tag, runtime ships only the venv + source tree + Python.
No build tools, no package manager, no shell.

## Run — two-instance lotor deployment shape

Scott runs two parallel instances on lotor with different OAuth credentials —
one for the Gmail-account workspace, one for the Red Hat workspace. Each lives
under its own `/srv/<name>.crunchtools.com/` tree following the crunchtools
service convention.

```bash
podman run -d --name google-workspace-personal --rm \
  --network crunchtools \
  -p 127.0.0.1:8011:8000 \
  -v /srv/google-workspace-personal.crunchtools.com/data:/app/data:Z \
  --env-file /srv/google-workspace-personal.crunchtools.com/config/google-workspace-personal.env \
  quay.io/crunchtools/google-workspace-mcp
```

```bash
podman run -d --name google-workspace-work --rm \
  --network crunchtools \
  -p 127.0.0.1:8010:8000 \
  -v /srv/google-workspace-work.crunchtools.com/data:/app/data:Z \
  --env-file /srv/google-workspace-work.crunchtools.com/config/google-workspace-work.env \
  quay.io/crunchtools/google-workspace-mcp
```

Both bind to `127.0.0.1` only — never public. Josui reaches them via the
Breetai → lotor SSH tunnel (`~/.config/systemd/user/lotor-mcp-tunnel.service`);
Kagetora reaches them by container DNS (`http://google-workspace-personal:8000/mcp`).

## Composition

- Base: `quay.io/hummingbird/python:3.13` (per the crunchtools image profile)
- Upstream: `taylorwilsdon/google_workspace_mcp` at `v${WORKSPACE_MCP_VERSION}` (build arg, default tracks the latest tested upstream tag)
- Multi-stage build; runtime carries no build tools, no shell, no package manager
- Streamable HTTP transport — same protocol the rest of the crunchtools MCP fleet speaks
- HEALTHCHECK probes the upstream's `/health` endpoint

## Configuration

The upstream's full config matrix is documented at
[workspacemcp.com](https://workspacemcp.com/). For the crunchtools deployment
the env file at `/srv/<name>.crunchtools.com/config/<name>.env` typically
contains the Google OAuth client ID + secret + scope set; the OAuth refresh
token lives in the bind-mounted data dir at `/app/data/credentials.json`.

OAuth refresh tokens are bound to the OAuth *application* (client ID), not the
host, so copying the existing token from Breetai to lotor works without
re-consent — same client, same scopes.

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
