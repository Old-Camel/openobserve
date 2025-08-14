FROM public.ecr.aws/docker/library/node:18.20.4-bookworm AS webbuilder
WORKDIR /web
COPY ./web /web/

# 加速 npm：仅设置国内 registry 镜像
RUN npm config set registry https://registry.npmmirror.com/

# 优先使用 npm ci（存在 lockfile 更快更稳定），否则回退 npm install
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
RUN NODE_OPTIONS="--max-old-space-size=8192" npm run build

FROM public.ecr.aws/zinclabs/rust:bookworm-sccache AS builder

# RUN rustup toolchain install nightly-2025-05-20
# RUN rustup default nightly-2025-05-20
# RUN rustup target add x86_64-unknown-linux-gnu
# RUN diff -u <(rustc --print cfg) <(rustc -C target-cpu=native --print cfg)
RUN rustc --version && sccache --version

# Cargo 加速：使用 rsproxy 镜像与 git cli 拉取
RUN set -eux; \
    mkdir -p /root/.cargo; \
    printf "[source.crates-io]\nreplace-with = 'rsproxy-sparse'\n\n[source.rsproxy]\nregistry = 'https://rsproxy.cn/crates.io-index'\n\n[source.rsproxy-sparse]\nregistry = 'sparse+https://rsproxy.cn/index/'\n\n[registries.rsproxy]\nindex = 'https://rsproxy.cn/crates.io-index'\n\n[net]\ngit-fetch-with-cli = true\n" > /root/.cargo/config.toml

WORKDIR /openobserve
COPY . /openobserve
COPY --from=webBuilder /web/dist web/dist

RUN cargo build --release

# FROM gcr.io/distroless/cc as runtime
FROM public.ecr.aws/debian/debian:bookworm-slim AS runtime
RUN set -eux; \
    # 1) 先使用 http 源以避免证书校验死锁，再安装 ca-certificates
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
COPY --from=builder /openobserve/target/release/openobserve /
RUN ["/openobserve", "init-dir", "-p", "/data/"]
CMD ["/openobserve"]
