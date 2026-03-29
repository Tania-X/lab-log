#!/bin/bash
# Lab Log 前端部署脚本
# 用于单独部署和测试前端 Nginx 服务

set -eu

# 配置
PROJECT_DIR="/home/lablog"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/lab-log/docker/docker-compose.yml"
LOG_FILE="$PROJECT_DIR/logs/deploy-frontend.log"

# 日志记录函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检测 Docker Compose 命令
detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# 健康检查
health_check() {
    local url=$1
    local max_retries=10
    local retry_delay=3

    for i in $(seq 1 $max_retries); do
        if curl -f "$url" > /dev/null 2>&1; then
            return 0
        fi
        log "⏳ 检查中... ($i/$max_retries)"
        sleep $retry_delay
    done
    return 1
}

# Nginx 健康检查（检查 Nginx 自身是否运行）
nginx_health_check() {
    local max_retries=10
    local retry_delay=3

    for i in $(seq 1 $max_retries); do
        # 使用 /nginx-health 端点检查 Nginx 自身，不依赖后端
        if curl -f "http://localhost/nginx-health" > /dev/null 2>&1; then
            return 0
        fi
        log "⏳ 检查 Nginx 中... ($i/$max_retries)"
        sleep $retry_delay
    done
    return 1
}

# 获取服务器 IP
get_server_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "your-server-ip")
    fi
    echo "$ip"
}

# 主程序
echo "🌐 Lab Log 前端部署脚本"
echo ""

# 检测 Docker Compose
DC=$(detect_docker_compose)
if [ -z "$DC" ]; then
    log "❌ Docker Compose 未安装"
    exit 1
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    log "❌ Docker 未安装"
    exit 1
fi

# 创建日志目录
mkdir -p "$PROJECT_DIR/logs"

# 进入项目目录
cd "$PROJECT_DIR/lab-log/docker"

# 检查后端是否运行
log "🔍 检查后端 API 状态..."
if ! curl -f "http://localhost:8000/health" > /dev/null 2>&1; then
    log "⚠️  后端 API 未运行，请先运行 deploy-backend.sh"
    exit 1
fi
log "✅ 后端 API 运行中"

# 构建并启动前端服务
log "🌐 构建并启动前端服务..."
if ! $DC -f "$DOCKER_COMPOSE_FILE" stop nginx 2>/dev/null; then
    log "⚠️  停止前端服务失败（可能未运行）"
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" build nginx; then
    log "❌ 构建前端镜像失败"
    exit 1
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d nginx; then
    log "❌ 启动前端服务失败"
    exit 1
fi

# 健康检查
log "🔍 检查 Nginx 健康状态..."
if nginx_health_check; then
    SERVER_IP=$(get_server_ip)
    log "✅ Nginx 运行正常"
    log ""
    log "🎉 前端部署完成！"
    log "📍 访问地址: http://$SERVER_IP"
    log "📍 API 文档: http://$SERVER_IP/api/docs"
else
    log "❌ Nginx 启动失败"
    $DC -f "$DOCKER_COMPOSE_FILE" logs nginx | tail -50
    exit 1
fi
