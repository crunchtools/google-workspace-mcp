# Google Workspace MCP server — crunchtools deployment.
# Wraps the upstream taylorwilsdon/google_workspace_mcp under the crunchtools
# container image profile: Hummingbird Python 3.13 distroless runtime,
# multi-stage build, no build tools or package manager in the runtime image.
#
# Build:
#   podman build -t quay.io/crunchtools/google-workspace-mcp .
#
# Run (the canonical two-instance lotor deployment shape):
#   podman run -d --name google-workspace-personal \
#     --rm \
#     --network crunchtools \
#     -p 127.0.0.1:8011:8000 \
#     -v /srv/google-workspace-personal.crunchtools.com/data:/app/data:Z \
#     --env-file /srv/google-workspace-personal.crunchtools.com/config/google-workspace-personal.env \
#     quay.io/crunchtools/google-workspace-mcp
#
# The upstream project is invoked via main.py at the source root (no PyPI
# entry point); we copy the full source tree in alongside the installed venv
# so the entrypoint can resolve all of upstream's auth/, gworkspace/, etc.
# submodules at import time.

# Stage 1: Install upstream + its deps into a venv
FROM quay.io/hummingbird/python:3.13-builder AS builder

# Hummingbird's distroless builder defaults to a non-root user that can't
# write to /app — switch to root for the build (it's discarded anyway).
USER 0

WORKDIR /build

# Hummingbird's python:3.13-builder doesn't ship git in its default set —
# install it just for the upstream clone (this whole stage is discarded anyway).
RUN microdnf install -y --nodocs git && microdnf clean all

# We pull the upstream source at a pinned tag for reproducible builds.
ARG WORKSPACE_MCP_VERSION=1.21.2
RUN git clone --depth 1 --branch v${WORKSPACE_MCP_VERSION} \
        https://github.com/taylorwilsdon/google_workspace_mcp.git /build/src

# Install upstream's deps + project into an isolated venv we'll lift into runtime.
# Upstream uses uv with uv.lock; pip install . is equivalent for the
# pyproject.toml's setuptools backend and avoids carrying uv into the runtime.
RUN python3.13 -m venv /app/venv && \
    /app/venv/bin/pip install --no-cache-dir /build/src

# Stash the source tree in /app/source — main.py and its sibling auth/, etc.
# modules all need to live together at runtime (they import each other relatively).
RUN cp -r /build/src /app/source && \
    rm -rf /app/source/.git

# Stage 2: Minimal runtime — distroless Hummingbird, no build tools, no shell.
FROM quay.io/hummingbird/python:3.13

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="Google Workspace MCP server (Gmail, Calendar, Drive, Docs, Sheets, Slides) — crunchtools deployment of taylorwilsdon/google_workspace_mcp under the crunchtools container image profile."
LABEL org.opencontainers.image.source="https://github.com/crunchtools/google-workspace-mcp"
LABEL org.opencontainers.image.title="google-workspace-mcp"
LABEL org.opencontainers.image.description="MCP server for Google Workspace (Calendar, Gmail, Docs, Sheets, Slides, Drive) — crunchtools deployment of taylorwilsdon/google_workspace_mcp."
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="crunchtools"

WORKDIR /app/source

# Bring in the installed venv and the upstream source tree.
COPY --from=builder /app/venv /app/venv
COPY --from=builder /app/source /app/source

ENV PATH="/app/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    HOME=/app

EXPOSE 8000

# Health probe — upstream exposes /health on the same streamable-http port.
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD ["/app/venv/bin/python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5).status == 200 else 1)"]

# Invoke upstream's main.py directly. Streamable-HTTP transport with bind on
# 0.0.0.0 inside the container so podman's port publishing reaches it; OAuth
# credentials, scope config, etc. all arrive via env vars from the systemd unit.
ENTRYPOINT ["/app/venv/bin/python", "/app/source/main.py"]
CMD ["--transport", "streamable-http", "--host", "0.0.0.0", "--port", "8000"]
