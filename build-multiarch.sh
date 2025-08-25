#!/bin/bash

# OpenObserve 多架构镜像构建脚本（优化版）
# 基于 deploy/build 目录下的 Dockerfile

# 声明变量
BASE_DIR=$(pwd)
LOG_PREFIX='[OpenObserve Build] '
# PUBLIC_IMAGE_NAME=xuch/openobserve
PUBLIC_IMAGE_NAME=swr.cn-north-1.myhuaweicloud.com/yunzai/openobserve

# 检查是否提供了标签参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <tag>"
    echo "示例: $0 v1"
    echo "示例: $0 latest"
    exit 1
fi

VERSION_TAG=$1

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}${LOG_PREFIX}${1}${NC}"
}

log_warn() {
    echo -e "${YELLOW}${LOG_PREFIX}${1}${NC}"
}

log_error() {
    echo -e "${RED}${LOG_PREFIX}${1}${NC}"
}

# 缓存状态检查函数
check_cache_status() {
    local cache_dir="$1"
    if [ -d "$cache_dir" ]; then
        local cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        local file_count=$(find "$cache_dir" -type f 2>/dev/null | wc -l)
        if [ -n "$cache_size" ]; then
            log_info "缓存目录大小: $cache_size，文件数量: $file_count"
        fi
    fi
}

# 检查是否在正确的目录
if [ ! -f "Cargo.toml" ]; then
    log_error "请在 OpenObserve 项目根目录下执行此脚本"
    exit 1
fi

# 检查 Docker 连接
log_info "检查 Docker 连接..."
if ! docker info > /dev/null 2>&1; then
    log_error "无法连接到 Docker 守护进程，请检查 Docker 是否运行"
    exit 1
fi

# 检查 buildx 是否可用
if ! docker buildx version > /dev/null 2>&1; then
    log_error "docker buildx 不可用，请先安装或启用 buildx"
    exit 1
fi

# 创建或检查构建器
BUILDER_NAME="openobserve-builder"
if ! docker buildx inspect "$BUILDER_NAME" > /dev/null 2>&1; then
    log_info "创建专用构建器: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use --driver docker-container
else
    log_info "使用现有构建器: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
fi

# 创建缓存目录
CACHE_DIR="$HOME/.buildx-cache/openobserve"
if ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
    log_warn "无法在用户主目录创建缓存，使用项目目录"
    CACHE_DIR="$(pwd)/.buildx-cache"
    mkdir -p "$CACHE_DIR"
fi

# 检查并清理损坏的缓存
if [ -d "$CACHE_DIR" ] && [ ! -f "$CACHE_DIR/index.json" ]; then
    log_warn "检测到损坏的缓存，清理中..."
    rm -rf "$CACHE_DIR"
    mkdir -p "$CACHE_DIR"
fi

log_info "缓存目录: $CACHE_DIR"
check_cache_status "$CACHE_DIR"

# 创建 .dockerignore 文件以减少构建上下文
log_info "创建 .dockerignore 文件..."
cat > .dockerignore << 'EOF'
# 构建产物和缓存
target/
.buildx-cache/
node_modules/
dist/
build/

# 版本控制
.git/
.gitignore

# IDE和编辑器
.vscode/
.idea/
*.swp
*.swo
*~

# 系统文件
.DS_Store
Thumbs.db

# 日志文件
*.log
logs/

# 测试覆盖率
coverage/

# 临时文件
tmp/
temp/
*.tmp

# 文档（除非需要）
docs/
*.md
!README.md

# 其他大文件
*.tar.gz
*.zip
*.deb
*.rpm
EOF

cd ${BASE_DIR}
log_info "开始构建 OpenObserve 多架构镜像: ${PUBLIC_IMAGE_NAME}:${VERSION_TAG}"

# 构建参数 - 明确指定 HTTP 协议
BUILD_ARGS=(
    "--platform" "linux/amd64,linux/arm64"
    "--provenance=false"
    "--build-arg" "BUILDKIT_INLINE_CACHE=1"
    "--build-arg" "DOCKER_BUILDKIT=1"
    "-f" "deploy/build/Dockerfile"
    "-t" "${PUBLIC_IMAGE_NAME}:${VERSION_TAG}"
    "--push"
    "--progress=plain"
)

# 添加缓存参数
if [ -d "$CACHE_DIR" ] && [ -w "$CACHE_DIR" ]; then
    # 检查缓存是否有内容
    if [ -n "$(ls -A "$CACHE_DIR" 2>/dev/null)" ] && [ -f "$CACHE_DIR/index.json" ]; then
        log_info "使用本地缓存构建..."
        BUILD_ARGS+=(
            "--cache-from" "type=local,src=$CACHE_DIR"
            "--cache-to" "type=local,dest=$CACHE_DIR,mode=max"
        )
    else
        log_info "本地缓存为空或损坏，仅设置缓存写入..."
        BUILD_ARGS+=(
            "--cache-to" "type=local,dest=$CACHE_DIR,mode=max"
        )
    fi

    # 尝试从远程拉取缓存（作为备用）
    BUILD_ARGS+=(
        "--cache-from" "type=registry,ref=${PUBLIC_IMAGE_NAME}:cache"
    )
else
    log_warn "缓存目录不可用，不使用缓存构建"
fi

# 执行构建
log_info "执行构建命令..."
echo "命令: docker buildx build ${BUILD_ARGS[*]} ."

if docker buildx build "${BUILD_ARGS[@]}" .; then
    log_info "多架构镜像构建成功！"
else
    log_error "多架构镜像构建失败！"
    exit 1
fi

# 检查构建后缓存状态
echo ""
log_info "构建完成后的缓存状态:"
check_cache_status "$CACHE_DIR"

# 显示构建结果
echo ""
log_info "构建结果:"
echo "  多架构版本: ${PUBLIC_IMAGE_NAME}:${VERSION_TAG} (支持 AMD64 和 ARM64)"

# 可选：推送缓存镜像
echo ""
read -p "是否推送缓存镜像到仓库？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "推送缓存镜像..."
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --cache-from type=local,src="$CACHE_DIR" \
        --cache-to type=registry,ref="${PUBLIC_IMAGE_NAME}:cache",mode=max \
        -f deploy/build/Dockerfile \
        -t ${PUBLIC_IMAGE_NAME}:cache-temp \
        . \
        --push > /dev/null 2>&1
    log_info "缓存镜像已推送"
fi

log_info "脚本执行完毕！"

# 询问是否清理缓存
echo ""
read -p "是否清理构建缓存？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "清理构建缓存..."
    rm -rf "$CACHE_DIR"
    docker buildx prune -f
    log_info "缓存已清理"
else
    log_info "缓存已保留，下次构建将使用缓存加速"
    check_cache_status "$CACHE_DIR"
fi

# 清理临时文件
rm -f .dockerignore