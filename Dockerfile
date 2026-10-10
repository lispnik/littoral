# Every example and demo in one container:
#
#   make docker
#   docker run --rm -p 127.0.0.1:8080:8080 littoral-demo
#
# The image is built from the executable `make build` writes.  It copies the
# dependencies in ocicl/, so run `ocicl install` first (make docker does).

FROM ubuntu:24.04 AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends sbcl gcc libc6-dev make ca-certificates libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN sbcl --non-interactive \
      --eval '(asdf:initialize-source-registry (quote (:source-registry (:directory "/src/") (:tree "/src/ocicl/") :ignore-inherited-configuration)))' \
      --load tools/demo-server.lisp --eval '(littoral-demo:build "/src/bin/littoral-demo")'

FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /data littoral
COPY --from=build /src/bin/littoral-demo /usr/local/bin/littoral-demo
USER littoral
WORKDIR /data
ENV PORT=8080 ADDRESS=0.0.0.0 DATA_DIR=/data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" || exit 1
CMD ["littoral-demo"]
