# Pinned build image for TDLib (Android NDK + Emscripten).
# Build: docker build -f Dockerfile -t oxplayer-tdlib-build .
# Then run td/example/web scripts inside the container with TD sources mounted at /td.

FROM ubuntu:22.04

ARG ANDROID_NDK_VERSION=26.1.10909125
# TD example/web enforces this Emscripten line (emcc 3.1.1 check).
ARG EMSDK_VERSION=3.1.1

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_NDK_HOME=/opt/android-ndk \
    EMSDK=/opt/emsdk

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    default-jdk-headless \
    git \
    gperf \
    ninja-build \
    php-cli \
    python3 \
    unzip \
    wget \
    zip \
    zlib1g-dev \
    libssl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Android NDK r26b (revision 26.1.10909125) — zip layout uses android-ndk-r26b
RUN wget -q "https://dl.google.com/android/repository/android-ndk-r26b-linux.zip" -O /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt \
    && mv /opt/android-ndk-r26b "${ANDROID_NDK_HOME}" \
    && rm /tmp/ndk.zip

# Emscripten: shallow clone of emsdk repo, then pin with explicit install/activate (not emsdk "latest").
RUN git clone --depth 1 https://github.com/emscripten-core/emsdk.git "${EMSDK}" \
    && /bin/bash -c "set -euo pipefail; cd \"${EMSDK}\" && ./emsdk install ${EMSDK_VERSION} && ./emsdk activate ${EMSDK_VERSION}"

# Default shell loads emsdk
RUN echo "source ${EMSDK}/emsdk_env.sh" >> /root/.bashrc

WORKDIR /workspace

# Next steps (run in CI with a volume mount):
#   git clone --depth 1 --branch v1.8.0 https://github.com/tdlib/td /td
#   cd /td/example/web && ./build-openssl.sh && ./build-tdlib.sh && ./copy-tdlib.sh && ./build-tdweb.sh
#   tar -czf /out/dist.tar.gz -C tdweb dist
#   cp build/tdjson/libtdjson.so ... (per ABI from separate NDK cmake builds)

CMD ["/bin/bash", "-lc", "source /opt/emsdk/emsdk_env.sh && emcc --version && cmake --version && echo ANDROID_NDK_HOME=$ANDROID_NDK_HOME"]
