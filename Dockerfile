FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bison ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      chmod +x build-linux-arm64.sh && ./build-linux-arm64.sh headless; \
    else \
      chmod +x build-linux-amd64.sh && ./build-linux-amd64.sh headless; \
    fi

# --- Runtime image ---
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /inferno

# Emulator binary
COPY --from=builder /src/emu/Linux/o.emu /inferno/emu
# Runtime tree
COPY --from=builder /src/dis /inferno/dis
COPY --from=builder /src/lib /inferno/lib
COPY --from=builder /src/fonts /inferno/fonts
COPY --from=builder /src/module /inferno/module
COPY --from=builder /src/services /inferno/services
COPY --from=builder /src/locale /inferno/locale
# mkconfig and mkfiles for building from source inside container
COPY --from=builder /src/mkconfig /inferno/mkconfig
COPY --from=builder /src/mkfiles /inferno/mkfiles

RUN mkdir -p /inferno/tmp /inferno/usr/inferno /inferno/mnt

EXPOSE 6668 6673

ENTRYPOINT ["/inferno/emu", "-c1", "-r", "/inferno"]
