#!/bin/bash

# OpenObserve 多架构镜像构建脚本
# 基于 deploy/build 目录下的 Dockerfile

# 声明变量
BASE_DIR=$(pwd)
LOG_PREFIX='[OpenObserve Build] '
PUBLIC_IMAGE_NAME=222.30.195.212:10000/cloud/openobserve

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

# 检查是否在正确的目录
if [ ! -f "Cargo.toml" ]; then
    log_error "请在 OpenObserve 项目根目录下执行此脚本"
    exit 1
fi

# 检查 buildx 是否可用
if ! docker buildx version > /dev/null 2>&1; then
    log_error "docker buildx 不可用，请先安装或启用 buildx"
    exit 1
fi

# 创建并使用新的构建器（如果需要）
BUILDER_NAME="openobserve-multiarch"
if ! docker buildx inspect $BUILDER_NAME > /dev/null 2>&1; then
    log_info "创建新的构建器: $BUILDER_NAME"
    docker buildx create --name $BUILDER_NAME --use
fi

# 使用构建器
docker buildx use $BUILDER_NAME

cd ${BASE_DIR}
log_info "开始构建 OpenObserve 多架构镜像: ${PUBLIC_IMAGE_NAME}:${VERSION_TAG}"

# 使用 buildx 一次性构建两个架构
log_info "构建多架构镜像 (AMD64 + ARM64)..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --provenance=false \
    -f deploy/build/Dockerfile \
    -t ${PUBLIC_IMAGE_NAME}:${VERSION_TAG} \
    . \
    --push

if [ $? -ne 0 ]; then
    log_error "多架构镜像构建失败！"
    exit 1
fi

log_info "多架构镜像构建成功！"

# 显示构建结果
echo ""
log_info "构建结果:"
echo "  多架构版本: ${PUBLIC_IMAGE_NAME}:${VERSION_TAG} (支持 AMD64 和 ARM64)"

log_info "脚本执行完毕！"
