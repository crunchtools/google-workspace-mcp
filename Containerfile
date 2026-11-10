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

# Install upstream's deps + project into an isolated venv we'll lift into
# runtime. Export upstream's own committed uv.lock to a requirements file and
# install from it with --no-deps, so transitive versions come from the lock
# upstream tested against -- not a fresh pip resolve of its loose
# pyproject.toml constraints.
RUN python3.13 -m venv /app/venv

RUN pip install --no-cache-dir uv==0.13.7
RUN cd /build/src && uv export --frozen --no-dev --no-emit-project --format requirements-txt -o /requirements.txt
RUN /app/venv/bin/pip install --no-cache-dir --no-deps -r /requirements.txt
RUN /app/venv/bin/pip install --no-cache-dir --no-deps /build/src

# Upstream's pyproject.toml only requires setuptools>=61.0 and doesn't pin
# msgpack directly (it's transitive), so pip resolves whatever the venv's
# bundled setuptools and the dependency tree's oldest-satisfying msgpack
# happen to be -- not necessarily current. Force both to the CVE-fixed
# versions post-install; upstream's own constraints are loose enough that
# this doesn't fight the resolver.
#   - msgpack 1.1.2 -> 1.2.1: GHSA-6v7p-g79w-8964 (out-of-bounds read/crash
#     on Unpacker reuse after error, HIGH)
#   - setuptools 70.3.0 -> 78.1.1: CVE-2025-47273 (path traversal in
#     PackageIndex, HIGH)
RUN /app/venv/bin/pip install --no-cache-dir --upgrade \
        'msgpack>=1.2.1' 'setuptools>=78.1.1'

# The upgrade above only touches the top-level packages -- it does not touch
# pip's OWN internally vendored copies. pip bundles frozen, unrelated
# snapshots of msgpack and setuptools/pkg_resources under pip/_vendor for its
# own use (see pip/_vendor/vendor.txt); pip 26.2 vendors msgpack==1.1.2 and
# setuptools==70.3.0, the exact same CVEs, and `pip install --upgrade` cannot
# reach code bundled inside pip itself. This is why the bump above alone
# still failed the Trivy gate. Since this image never invokes pip at runtime
# (venv is built once here; the runtime stage only runs main.py), the real
# fix is to remove pip from the shipped venv entirely, matching this
# Containerfile's own "no build tools in the runtime image" intent, which
# pip's presence here was quietly violating anyway.
RUN /app/venv/bin/python -m pip uninstall -y pip && \
    rm -rf /app/venv/lib/python3.13/site-packages/pip* \
           /app/venv/bin/pip /app/venv/bin/pip3 /app/venv/bin/pip3.13

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

# Remove the base image's own pip. pip 26.2 vendors frozen copies of setuptools
# 70.3.0 (CVE-2025-47273) and urllib3 2.7.0 (CVE-2026-97687/97689) under
# pip/_vendor, which Trivy flags under the pathless "Python" target even though
# nothing here ever runs pip (entrypoint is the venv's python on main.py; the
# venv's own pip was already removed in the builder). Distroless runtime has no
# shell, so delete with the venv python; /usr/local is root-owned, hence USER 0.
USER 0
RUN ["/app/venv/bin/python", "-c", "import glob,shutil,os; [shutil.rmtree(p,ignore_errors=True) for p in glob.glob('/usr/local/lib/python3.*/site-packages/pip*')]; [os.remove(p) for p in glob.glob('/usr/local/bin/pip*') if os.path.exists(p)]"]
USER 65532

ENV PATH="/app/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    HOME=/app

EXPOSE 8000

# Health probe — upstream exposes /health on the same streamable-http port.
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD ["/app/venv/bin/python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5).status == 200 else 1)"]

# Invoke upstream's main.py directly. Upstream's argparse only accepts
# `--transport` + a handful of TOOL_TIER/TOOLS pass-throughs; host/port are
# controlled by fastmcp's defaults (binds 0.0.0.0:8000) plus env vars
# (WORKSPACE_MCP_PORT, etc.) so don't pass --host/--port as CLI args.
ENTRYPOINT ["/app/venv/bin/python", "/app/source/main.py"]
CMD ["--transport", "streamable-http"]
