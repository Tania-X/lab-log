# 使用 uv 管理 Python 环境和依赖 (Windows)

本项目使用 `uv` 来管理 Python 环境和依赖包。uv 会自动管理虚拟环境，无需手动激活。

## 环境要求

- Windows 10/11
- 已安装 uv（安装方式见下文）

## 安装 uv

```powershell
# 使用 pip 安装
pip install uv

# 或使用 PowerShell 脚本安装（推荐）
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

## 快速开始

### 1. 进入项目目录

```powershell
# 改为自己的目录
cd D:\my_projects\lab-log
```

### 2. 同步依赖

```powershell
uv sync
```

这会读取 `pyproject.toml` 和 `uv.lock` 文件，自动安装所有依赖。

### 3. 使用 uv 运行命令

```powershell
# 运行脚本
uv run python scripts/init_database.py

# 运行 API 服务器
uv run uvicorn web_api.main:app --reload --host 0.0.0.0 --port 8000

# 运行其他 Python 脚本
uv run python scripts/process_video.py
```

> **注意**：使用 `uv run` 时，uv 会自动使用项目依赖，无需手动激活虚拟环境。

## 镜像源配置

已配置使用清华镜像源加速下载，配置位于 `pyproject.toml`：

```toml
[[tool.uv.index]]
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true
```

如需临时使用其他镜像源，可设置环境变量：

```powershell
# CMD
set UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

# PowerShell
$env:UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
```

## 常用命令

```powershell
# 同步依赖（根据 pyproject.toml 和 uv.lock）
uv sync

# 添加新依赖
uv add package_name

# 添加开发依赖
uv add --dev package_name

# 查看已安装的包
uv pip list

# 更新依赖
uv sync --upgrade

# 运行 Python 脚本
uv run python script.py

# 进入 Python 交互式环境
uv run python
```

## 项目结构说明

- `pyproject.toml` - 项目配置和依赖定义
- `uv.lock` - 依赖锁定文件（确保环境一致性）
- `.venv/` - uv 自动管理的虚拟环境目录（已在 .gitignore 中）

## 优势

- **速度快**：uv 使用 Rust 编写，比 pip 快 10-100 倍
- **可靠**：更好的依赖解析和锁定
- **简单**：统一的工具管理虚拟环境和包
- **无需激活**：使用 `uv run` 自动处理环境

## 注意事项

- 虚拟环境位于 `.venv/` 目录，由 uv 自动管理
- `.venv/` 已在 `.gitignore` 中，不会提交到版本控制
- 所有操作都使用 `uv` 命令，无需手动激活虚拟环境
- 依赖定义统一在 `pyproject.toml` 中管理
