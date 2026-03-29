#!/bin/bash
# Lab Log 数据库部署脚本
# 用于单独部署和测试数据库服务

set -eu

# 配置
PROJECT_DIR="/home/lablog"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/lab-log/docker/docker-compose.yml"
LOG_FILE="$PROJECT_DIR/logs/deploy-db.log"

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

# 主程序
echo "🗄️  Lab Log 数据库部署脚本"
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

# 进入项目目录
cd "$PROJECT_DIR/lab-log/docker"

# 创建日志目录
mkdir -p "$PROJECT_DIR/logs"

# 创建数据目录（在 docker 目录下）
mkdir -p "$PROJECT_DIR/lab-log/docker/data/seekdb"
log "✅ 数据目录已准备: $PROJECT_DIR/lab-log/docker/data/seekdb"

# 停止并启动数据库服务
log "🗄️  启动数据库服务..."
if ! $DC -f "$DOCKER_COMPOSE_FILE" stop db 2>/dev/null; then
    log "⚠️  停止数据库服务失败（可能未运行）"
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" rm -f db 2>/dev/null; then
    log "⚠️  删除旧数据库容器失败（可能不存在）"
fi
if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d db; then
    log "❌ 启动数据库服务失败"
    exit 1
fi

# 等待数据库启动
log "⏳ 等待数据库初始化..."
sleep 15

# 健康检查（使用 MySQL 连接测试）
log "🔍 检查数据库连接..."
for i in {1..10}; do
    if docker exec lab-log-db mysql -h127.0.0.1 -P2881 -uroot -e "SELECT 1" > /dev/null 2>&1; then
        log "✅ 数据库服务运行正常"
        log "📍 连接信息: localhost:2881"
        exit 0
    fi
    log "⏳ 检查中... ($i/10)"
    sleep 3
done

log "❌ 数据库服务启动失败"
$DC -f "$DOCKER_COMPOSE_FILE" logs db | tail -50
exit 1
