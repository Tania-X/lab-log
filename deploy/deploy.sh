#!/bin/bash
# Lab Log 服务器端部署脚本
# 融合 deploy-db.sh、deploy-backend.sh、deploy-frontend.sh 的功能
# 支持分阶段部署：db、backend、frontend、all

# 严格模式：-e 遇到错误退出，-u 变量未定义报错
set -eu

# ============ 配置区 ============
PROJECT_DIR="/home/lablog"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/lab-log/docker/docker-compose.yml"
LOG_FILE="$PROJECT_DIR/logs/deploy.log"
LOCK_FILE="/tmp/lab-log-deploy.lock"

# ============ 工具函数 ============

# 日志记录函数
# param $1 日志消息内容
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检测 Docker Compose 命令（兼容新旧版本）
# 无参数
detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# 获取服务器 IP（优先内网 IP）
# 无参数
get_server_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "your-server-ip")
    fi
    echo "$ip"
}

# 获取服务器 公网IP（如果可用）
# 无参数
get_public_ip() {
    local public_ip
    public_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
    echo "$public_ip"
}

# 检查是否已有部署在进行中
# 无参数
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        log "❌ 部署正在进行中，请等待完成后再试"
        exit 1
    fi
}

# 创建锁文件
# 无参数
create_lock() {
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; log "清理锁文件"' EXIT
}

# 检查指定容器是否正在运行
# param $1 container_name 容器名称（不能为空）
# 返回值：0-运行中，1-未运行或参数错误
is_container_running() {
    local container_name=$1
    if [ -z "$container_name" ]; then
        return 1
    fi
    docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "$container_name"
}

# 加载容器名称配置
# 无参数
load_container_names() {
    local config_file="$PROJECT_DIR/lab-log/deploy/deploy.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
        log "✅ 已加载容器名称配置"
    else
        log "⚠️  容器名称配置文件不存在，使用默认值"
        BACKEND_CONTAINER_NAME="lab-log-api"
        FRONTEND_CONTAINER_NAME="lab-log-nginx"
        DB_CONTAINER_NAME="lab-log-db"
    fi
}

# 替换 docker-compose.yml 中的容器名称占位符
# 无参数
replace_container_names() {
    local compose_file="$DOCKER_COMPOSE_FILE"

    # 备份原文件
    cp "$compose_file" "$compose_file.bak"

    # 替换占位符
    sed -i "s/BACKEND_CONTAINER_NAME_PLACEHOLDER/$BACKEND_CONTAINER_NAME/g" "$compose_file"
    sed -i "s/FRONTEND_CONTAINER_NAME_PLACEHOLDER/$FRONTEND_CONTAINER_NAME/g" "$compose_file"
    sed -i "s/DB_CONTAINER_NAME_PLACEHOLDER/$DB_CONTAINER_NAME/g" "$compose_file"

    log "✅ 已替换 docker-compose.yml 中的容器名称"
}

# ============ 健康检查函数 ============

# 数据库健康检查（来自 deploy-db.sh）
# param $1 max_retries 最大重试次数（默认：10）
# param $2 retry_delay 每次重试间隔秒数（默认：3）
check_db_health() {
    local max_retries=${1:-10}
    local retry_delay=${2:-3}

    for i in $(seq 1 $max_retries); do
        if docker exec lab-log-db mysql -h127.0.0.1 -P2881 -uroot -e "SELECT 1" > /dev/null 2>&1; then
            return 0
        fi
        log "⏳ 数据库检查中... ($i/$max_retries)"
        sleep $retry_delay
    done
    return 1
}

# 后端 API 健康检查（来自 deploy-backend.sh）
# param $1 url 健康检查URL（默认：http://localhost:8000/health）
# param $2 max_retries 最大重试次数（默认：15）
# param $3 retry_delay 每次重试间隔秒数（默认：3）
check_backend_health() {
    local url=${1:-"http://localhost:8000/health"}
    local max_retries=${2:-15}
    local retry_delay=${3:-3}

    for i in $(seq 1 $max_retries); do
        if curl -f "$url" > /dev/null 2>&1; then
            return 0
        fi
        log "⏳ 后端 API 检查中... ($i/$max_retries)"
        sleep $retry_delay
    done
    return 1
}

# Nginx 健康检查（来自 deploy-frontend.sh）
# param $1 max_retries 最大重试次数（默认：10）
# param $2 retry_delay 每次重试间隔秒数（默认：3）
check_nginx_health() {
    local max_retries=${1:-10}
    local retry_delay=${2:-3}

    for i in $(seq 1 $max_retries); do
        if curl -f "http://localhost/nginx-health" > /dev/null 2>&1; then
            return 0
        fi
        log "⏳ Nginx 检查中... ($i/$max_retries)"
        sleep $retry_delay
    done
    return 1
}

# ============ 部署函数 ============

# 部署数据库（来自 deploy-db.sh）
# 无参数
deploy_db() {
    log "🗄️  开始部署数据库..."

    # 创建数据目录
    mkdir -p "$PROJECT_DIR/lab-log/docker/data/seekdb"
    log "✅ 数据目录已准备"

    # 停止并删除旧容器
    log "🛑 停止旧数据库服务..."
    if ! $DC -f "$DOCKER_COMPOSE_FILE" stop db 2>/dev/null; then
        log "⚠️  停止数据库服务失败（可能未运行）"
    fi
    if ! $DC -f "$DOCKER_COMPOSE_FILE" rm -f db 2>/dev/null; then
        log "⚠️  删除旧数据库容器失败（可能不存在）"
    fi

    # 启动数据库服务
    log "▶️  启动数据库服务..."
    if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d db; then
        log "❌ 启动数据库服务失败"
        return 1
    fi

    # 等待数据库初始化
    log "⏳ 等待数据库初始化..."
    sleep 15

    # 健康检查
    log "🔍 检查数据库连接..."
    if check_db_health 10 3; then
        log "✅ 数据库服务运行正常"
        log "📍 连接信息: localhost:2881"
        return 0
    else
        log "❌ 数据库服务启动失败"
        $DC -f "$DOCKER_COMPOSE_FILE" logs "$DB_CONTAINER_NAME" | tail -50
        return 1
    fi
}

# 部署后端（来自 deploy-backend.sh）
# 无参数
deploy_backend() {
    log "⚙️  开始部署后端..."

    # 检查 .env 文件
    local env_file="$PROJECT_DIR/lab-log/docker/.env"
    if [ ! -f "$env_file" ]; then
        log "❌ .env 文件不存在: $env_file"
        return 1
    fi
    log "✅ .env 文件已检查"

    # 检查数据库是否运行
    log "🔍 检查数据库状态..."
    if ! $DC -f "$DOCKER_COMPOSE_FILE" ps db | grep -q "Up"; then
        log "⚠️  数据库未运行，请先部署数据库"
        return 1
    fi
    log "✅ 数据库容器运行中"

    # 等待数据库就绪
    log "⏳ 等待数据库就绪..."
    if ! check_db_health 15 2; then
        log "❌ 数据库无法连接"
        return 1
    fi
    log "✅ 数据库已就绪"

    # 创建必要目录
    mkdir -p "$PROJECT_DIR/lab-log/docker/logs_debug" "$PROJECT_DIR/lab-log/docker/recordings"
    log "✅ 目录已准备"

    # 构建并启动后端服务
    log "🐳 构建并启动后端服务..."
    if ! $DC -f "$DOCKER_COMPOSE_FILE" stop api 2>/dev/null; then
        log "⚠️  停止后端服务失败（可能未运行）"
    fi
    if ! $DC -f "$DOCKER_COMPOSE_FILE" build api; then
        log "❌ 构建后端镜像失败"
        return 1
    fi
    if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d api; then
        log "❌ 启动后端服务失败"
        return 1
    fi

    # 健康检查
    log "🔍 检查后端容器状态..."
    if is_container_running "$BACKEND_CONTAINER_NAME"; then
        local public_ip=$(get_public_ip)
        log "✅ 后端容器 $BACKEND_CONTAINER_NAME 运行正常"
        log "📍 访问地址: http://$public_ip:8000"
        log "📍 API 文档: http://$public_ip:8000/docs"
        return 0
    else
        log "❌ 后端容器 $BACKEND_CONTAINER_NAME 未运行"
        $DC -f "$DOCKER_COMPOSE_FILE" logs "$BACKEND_CONTAINER_NAME" | tail -50
        return 1
    fi
}

# 部署前端（来自 deploy-frontend.sh）
# 无参数
deploy_frontend() {
    log "🌐 开始部署前端..."

    # 构建并启动前端服务
    log "🐳 构建并启动前端服务..."
    if ! $DC -f "$DOCKER_COMPOSE_FILE" stop nginx 2>/dev/null; then
        log "⚠️  停止前端服务失败（可能未运行）"
    fi
    if ! $DC -f "$DOCKER_COMPOSE_FILE" build nginx; then
        log "❌ 构建前端镜像失败"
        return 1
    fi
    if ! $DC -f "$DOCKER_COMPOSE_FILE" up -d nginx; then
        log "❌ 启动前端服务失败"
        return 1
    fi

    # 健康检查
    log "🔍 检查 Nginx 容器状态..."
    if is_container_running "$FRONTEND_CONTAINER_NAME"; then
        local server_ip=$(get_server_ip)
        log "✅ Nginx 容器 $FRONTEND_CONTAINER_NAME 运行正常"
        log "📍 访问地址: http://$server_ip"
        log "📍 API 文档: http://$server_ip/api/docs"
        return 0
    else
        log "❌ Nginx 容器 $FRONTEND_CONTAINER_NAME 未运行"
        $DC -f "$DOCKER_COMPOSE_FILE" logs "$FRONTEND_CONTAINER_NAME" | tail -50
        return 1
    fi
}

# ============ 主程序 ============

# 显示帮助信息
# 无参数
show_help() {
    echo "🚀 Lab Log 部署脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --mode=MODE    部署模式 (默认: all)"
    echo "                 all      - 完整部署 (db + backend + frontend)"
    echo "                 db       - 仅部署数据库"
    echo "                 backend  - 部署数据库和后端"
    echo "                 frontend - 仅部署前端"
    echo "  --help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                      # 完整部署"
    echo "  $0 --mode=db            # 仅部署数据库"
    echo "  $0 --mode=backend       # 部署数据库和后端"
    echo "  $0 --mode=frontend      # 仅部署前端"
}

# 解析参数
DEPLOY_MODE="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            DEPLOY_MODE="${1#*=}"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "❌ 未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证部署模式
if [[ ! "$DEPLOY_MODE" =~ ^(all|db|backend|frontend)$ ]]; then
    echo "❌ 无效的部署模式: $DEPLOY_MODE"
    show_help
    exit 1
fi

echo "🚀 Lab Log 部署脚本"
echo "📦 部署模式: $DEPLOY_MODE"
echo ""

# 检查项目目录
if [ ! -d "$PROJECT_DIR" ]; then
    log "❌ 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

# 创建日志目录
mkdir -p "$PROJECT_DIR/logs"
touch "$LOG_FILE"

# 检查锁
check_lock
create_lock

log "开始部署 Lab Log [模式: $DEPLOY_MODE]..."

# 加载容器名称配置
load_container_names

# 替换 docker-compose.yml 中的容器名称占位符
replace_container_names

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

# 根据模式执行部署
case $DEPLOY_MODE in
    db)
        deploy_db || exit 1
        ;;
    backend)
        deploy_db || exit 1
        deploy_backend || exit 1
        ;;
    frontend)
        deploy_frontend || exit 1
        ;;
    all)
        deploy_db || exit 1
        deploy_backend || exit 1
        deploy_frontend || exit 1
        ;;
esac

# 部署完成汇总
log ""
log "🎉 部署完成！"
log ""

SERVER_IP=$(get_server_ip)

# 根据模式显示相应信息
case $DEPLOY_MODE in
    db)
        log "📍 数据库连接: localhost:2881"
        ;;
    backend)
        log "📍 后端 API: http://localhost:8000"
        log "📍 API 文档: http://localhost:8000/docs"
        ;;
    frontend)
        log "📍 统一入口: http://$SERVER_IP"
        log "📍 API 文档: http://$SERVER_IP/api/docs"
        ;;
    all)
        log "📍 统一入口: http://$SERVER_IP"
        log "📍 API 文档: http://$SERVER_IP/api/docs"
        log "📍 数据库连接: localhost:2881"
        ;;
esac

log ""
log "📋 常用命令:"
log "  - 查看日志: $DC -f $DOCKER_COMPOSE_FILE logs -f"
log "  - 停止服务: $DC -f $DOCKER_COMPOSE_FILE down"
log "  - 重启服务: $DC -f $DOCKER_COMPOSE_FILE restart"
log "  - 查看状态: $DC -f $DOCKER_COMPOSE_FILE ps"
log ""
log "📝 部署日志: $LOG_FILE"
