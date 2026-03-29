#!/bin/bash
# Lab Log 后端部署脚本
# 用于单独部署和测试后端 API 服务

set -eu

# 配置
PROJECT_DIR="/home/lablog"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/lab-log/docker/docker-compose.yml"
LOG_FILE="$PROJECT_DIR/logs/deploy-backend.log"

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
    local max_retries=15
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

# 主程序
echo "⚙️  Lab Log 后端部署脚本"
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

# 检查 .env 文件
ENV_FILE="$PROJECT_DIR/lab-log/docker/.env"
if [ ! -f "$ENV_FILE" ]; then
    log "❌ .env 文件不存在: $ENV_FILE"
    log "请先创建 .env 文件或运行完整部署脚本"
    exit 1
fi
log "✅ .env 文件已检查"

# 检查数据库是否运行并等待就绪
log "🔍 检查数据库状态..."
if ! $DC -f "$DOCKER_COMPOSE_FILE" ps db | grep -q "Up"; then
    log "⚠️  数据库未运行，请先运行 deploy-db.sh"
    exit 1
fi
log "✅ 数据库容器运行中"

# 等待数据库就绪（可连接）
log "⏳ 等待数据库就绪..."
for i in {1..15}; do
    if docker exec lab-log-db mysql -h127.0.0.1 -P2881 -uroot -e "SELECT 1" > /dev/null 2>&1; then
        log "✅ 数据库已就绪"
        break
    fi
    log "⏳ 等待数据库就绪... ($i/15)"
    sleep 2
done

# 最终检查
if ! docker exec lab-log-db mysql -h127.0.0.1 -P2881 -uroot -e "SELECT 1" > /dev/null 2>&1; then
    log "❌ 数据库无法连接"
    exit 1
fi

# 创建必要目录
mkdir -p logs_debug recordings
log "✅ 目录已准备"

# 构建并启动后端服务
log "⚙️  构建并启动后端服务..."
if ! $DC -f "$DOCKER_COMPOSE_FILE" stop api 2>/dev/null; then
    log "⚠️  停止后端服务失败（可能未运行）"
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" build api; then
    log "❌ 构建后端镜像失败"
    exit 1
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d api; then
    log "❌ 启动后端服务失败"
    exit 1
fi

# 健康检查
log "🔍 检查后端 API 健康状态..."
if health_check "http://localhost:8000/health"; then
    log "✅ 后端 API 运行正常"
    log "📍 访问地址: http://localhost:8000"
    log "📍 API 文档: http://localhost:8000/docs"
else
    log "❌ 后端 API 启动失败"
    $DC -f "$DOCKER_COMPOSE_FILE" logs api | tail -50
    exit 1
fi
