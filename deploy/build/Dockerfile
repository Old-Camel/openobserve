# syntax=docker/dockerfile:1
FROM public.ecr.aws/docker/library/node:20.19.0-bookworm AS webbuilder
WORKDIR /web
COPY ./web /web/
RUN npm config set registry https://registry.npmmirror.com/

# 配置yarn使用国内镜像和网络优化
RUN npm install -g tyarn && \
    tyarn config set registry https://registry.npmmirror.com/ && \
    tyarn config set network-timeout 900000 && \
    tyarn config set network-concurrency 1 && \
    tyarn config set prefer-offline true

# 使用npm作为备选方案
RUN tyarn install || npm install
# 设置环境变量禁用visualizer自动打开浏览器，避免在容器中启动PowerShell
RUN DISABLE_VISUALIZER_OPEN=true NODE_OPTIONS="--max-old-space-size=8192" npm run build

FROM public.ecr.aws/zinclabs/rust:bookworm-sccache AS builder
ARG TARGETARCH
COPY .cargo/ ./.cargo/

RUN rustc --version && sccache --version

WORKDIR /openobserve
COPY . /openobserve
COPY --from=webbuilder /web/dist web/dist

ENV CARGO_BUILD_JOBS=15



# 统一的 sccache 配置 - 两个架构都使用本地缓存
RUN --mount=type=cache,target=/root/.cache/sccache,id=oo-sccache-${TARGETARCH},sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/openobserve/target \
    mkdir -p /openobserve/target/release/ && \
    mkdir -p /openobserve/final/ && \
    mkdir -p /root/.cache/sccache && \
    chmod -R 777 /root/.cache/sccache && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        echo "[builder] ARM64 build (no sccache) + mimalloc"; \
        export RUSTFLAGS="-C lto=off -C target-feature=+aes,+neon"; \
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc; \
        export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc; \
        export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++; \
        unset RUSTC_WRAPPER SCCACHE_NO_DAEMON SCCACHE_DIR SCCACHE_BUCKET SCCACHE_ENDPOINT SCCACHE_REGION SCCACHE_S3_USE_SSL SCCACHE_S3_FORCE_PATH_STYLE SCCACHE_S3_KEY_PREFIX || true; \
        # ARM64 禁用 sccache，直接构建 \
        cargo build --release -j 15 --features mimalloc --target aarch64-unknown-linux-gnu; \
        echo "=== ARM64 build output ===" && \
        ls -la /openobserve/target/aarch64-unknown-linux-gnu/release/ && \
        cp /openobserve/target/aarch64-unknown-linux-gnu/release/openobserve /openobserve/final/openobserve && \
        ls -la /openobserve/final/ && \
        true; \
    else \
        echo "[builder] x86_64 build (no sccache)"; \
        export RUSTFLAGS="-C lto=off -C target-cpu=native"; \
        # AMD64 禁用 sccache，直接构建 \
        unset RUSTC_WRAPPER SCCACHE_NO_DAEMON SCCACHE_DIR SCCACHE_BUCKET SCCACHE_ENDPOINT SCCACHE_REGION SCCACHE_S3_USE_SSL SCCACHE_S3_FORCE_PATH_STYLE SCCACHE_S3_KEY_PREFIX || true; \
        cargo build --release -j 15 --features mimalloc --target x86_64-unknown-linux-gnu; \
        echo "=== AMD64 build output ===" && \
        ls -la /openobserve/target/x86_64-unknown-linux-gnu/release/ && \
        cp /openobserve/target/x86_64-unknown-linux-gnu/release/openobserve /openobserve/final/openobserve && \
        ls -la /openobserve/final/ && \
        true; \
    fi

FROM public.ecr.aws/debian/debian:bookworm-slim AS runtime
RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i 's|https://|http://|g; s|deb.debian.org/debian|mirrors.aliyun.com/debian|g; s|security.debian.org/debian-security|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list.d/debian.sources; \
    else \
        echo 'deb http://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware' > /etc/apt/sources.list; \
        echo 'deb http://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware' >> /etc/apt/sources.list; \
        echo 'deb http://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    update-ca-certificates; \
    # 2) 有证书后切回 https 源并安装其余软件
    sed -i 's|http://mirrors.aliyun.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list || true; \
    sed -i 's|http://mirrors.aliyun.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources || true; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl htop iftop sysstat procps lsof net-tools; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /openobserve/final/openobserve /
RUN ["/openobserve", "init-dir", "-p", "/data/"]
CMD ["/openobserve"]