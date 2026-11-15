# syntax=docker/dockerfile:1.7
# Supply --build-context compat_source=<prepare_compat output>.
# The external context contains exact pinned PR #15/#16/#18 code, never a
# developer's active worktree. Docker does not fetch GitHub or provider data.
FROM rust:1.99.0-bookworm@sha256:114c7a4425406451c2866b6aafe69fe29b1b298832db1277d411ac73c82d04d6 AS rust-build
WORKDIR /source
COPY --from=compat_source /18/engine ./engine
COPY --from=compat_source /cargo-vendor ./vendor
RUN mkdir .cargo && printf '[source.crates-io]\nreplace-with = "vendored-sources"\n[source.vendored-sources]\ndirectory = "/source/vendor"\n' > .cargo/config.toml
RUN cargo build --offline --locked --release --manifest-path engine/Cargo.toml --example v03_demo

FROM python:3.12-slim-bookworm@sha256:935c3c5b12357a7e10caa9c1e6ca5692344d97cf229832ef584be2cec9fc03df
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app/server
WORKDIR /app
RUN apt-get update && apt-get install --no-install-recommends -y libexpat1 && rm -rf /var/lib/apt/lists/*
COPY server/requirements.lock /tmp/server/requirements.lock
COPY server/platform-v1/requirements.lock /tmp/server/platform-v1/requirements.lock
COPY --from=compat_source /wheels /tmp/wheels
RUN pip install --no-index --find-links=/tmp/wheels --no-cache-dir -r /tmp/server/platform-v1/requirements.lock \
    && rm -rf /tmp/wheels \
    && groupadd --gid 10001 earthsync \
    && useradd --uid 10001 --gid 10001 --no-create-home earthsync \
    && mkdir /data && chown 10001:10001 /data
RUN python -c "import rasterio, shapely; from PIL import Image"
COPY --chown=10001:10001 server/earthsync/__init__.py ./server/earthsync/__init__.py
COPY --chown=10001:10001 server/earthsync/platform_v1 ./server/earthsync/platform_v1
COPY --chown=10001:10001 server/earthsync/realtime ./server/earthsync/realtime
COPY --chown=10001:10001 server/earthsync/research ./server/earthsync/research
COPY --chown=10001:10001 data/crop-rule-candidates/v1 ./data/crop-rule-candidates/v1
COPY --chown=10001:10001 data/crop-knowledge/v2 ./data/crop-knowledge/v2
COPY --chown=10001:10001 --from=compat_source /16/server/earthsync/evidence ./server/earthsync/evidence
COPY --chown=10001:10001 --from=compat_source /15/data/crop-knowledge/v1/catalog.json /app/catalog.json
COPY --chown=10001:10001 --from=rust-build /source/engine/target/release/examples/v03_demo /app/v03_demo
COPY --chown=10001:10001 server/platform-v1/container_start.py /app/container_start.py
USER 10001:10001
ENV EARTHSYNC_PLATFORM_DIR=/data EARTHSYNC_V03_EXECUTABLE=/app/v03_demo EARTHSYNC_CATALOG_PATH=/app/catalog.json
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8021/api/platform/v1/ready', timeout=2)"
ENTRYPOINT ["python", "/app/container_start.py"]
