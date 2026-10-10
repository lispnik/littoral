# {{title}} in a container, from the executable `make build` writes:
#
#   make docker
#   docker run --rm -p 127.0.0.1:{{port}}:{{port}} -e PUBLIC_URL=https://example.org -v {{name}}-data:/data {{name}}
#
# Littoral and its dependencies come from your Littoral checkout (LITTORAL in
# the Makefile), passed to the build as the "littoral" context.

FROM ubuntu:24.04 AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends sbcl gcc libc6-dev make ca-certificates libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=littoral littoral.asd README.md /littoral/
COPY --from=littoral src /littoral/src
COPY --from=littoral static /littoral/static
COPY --from=littoral ocicl /littoral/ocicl
WORKDIR /app
COPY . .
RUN rm -rf bin && make build LITTORAL=/littoral/

FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /data {{name}}
COPY --from=build /app/bin/{{name}} /usr/local/bin/{{name}}
USER {{name}}
WORKDIR /data
ENV PORT={{port}} ADDRESS=0.0.0.0 DATA_DIR=/data
VOLUME /data
EXPOSE {{port}}
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" || exit 1
CMD ["{{name}}"]
