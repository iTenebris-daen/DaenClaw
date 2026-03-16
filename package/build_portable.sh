#!/bin/bash
echo "🚀 开始构建 OpenClaw 绿色版工程..."

# ================= 配置项 =================
PORTABLE_DIR="openclaw-portable"
NODE_VERSION=$(node -v) # 自动获取当前系统的 Node 版本
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz"
# ==========================================

# 1. 初始化目录结构
rm -rf "$PORTABLE_DIR"
mkdir -p "$PORTABLE_DIR"/{bin,lib,data/home,data/pw-browsers}

# 2. 下载并配置独立版 Node.js
echo "📦 [1/7] 正在下载并配置独立的 Node.js 环境 ($NODE_VERSION)..."
wget -qO- "$NODE_URL" | tar -xJ -C "$PORTABLE_DIR/bin" --strip-components=2 "node-${NODE_VERSION}-linux-x64/bin/node"
chmod +x "$PORTABLE_DIR/bin/node"

# 3. 完整拷贝全局 npm 依赖和可执行入口
echo "📂 [2/7] 正在拷贝 npm 全局依赖库..."
cp -a ~/.npm-global/lib/node_modules "$PORTABLE_DIR/lib/"
cp -a ~/.npm-global/bin "$PORTABLE_DIR/global-bin"

# 4. 拷贝并精简用户数据
echo "⚙️  [3/7] 正在拷贝并瘦身现有的 .openclaw 数据目录..."
if [ -d "$HOME/.openclaw" ]; then
    cp -r "$HOME/.openclaw" "$PORTABLE_DIR/data/home/"

    # ================= 数据清理逻辑开始 =================
    OPENCLAW_HOME="$PORTABLE_DIR/data/home/.openclaw"

    # 4.1 清理所有 openclaw.json 的备份文件 (保留原本的 openclaw.json)
    # 这会匹配 openclaw.json.bak, openclaw.json.bak.1, openclaw.json0225 等等
    find "$OPENCLAW_HOME" -maxdepth 1 -type f -name "openclaw.json*" ! -name "openclaw.json" -delete
    echo "   -> 已清理主配置文件历史备份"

    # 4.2 精简 workspace 目录
    WORKSPACE_DIR="$OPENCLAW_HOME/workspace"
    if [ -d "$WORKSPACE_DIR" ]; then
        find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 | while read -r item; do
            base_name=$(basename "$item")

            # 保留规则 A: 名字叫 skills 的目录
            if [ "$base_name" == "skills" ]; then
                continue
            fi

            # 保留规则 B: 纯大写字母的 .md 文件 (例如 AGENTS.md, BOOTSTRAP.md)
            if [[ "$base_name" =~ ^[A-Z]+\.md$ ]]; then
                continue
            fi

            # 不符合上述规则的，直接干掉
            rm -rf "$item"
        done
        echo "   -> 已精简 workspace (仅保留 skills 目录与核心大写 MD 设定文件)"
    fi
    # ================= 数据清理逻辑结束 =================

else
    echo "⚠️ 警告: 未在宿主机找到 ~/.openclaw 目录，你的绿色包可能缺少基础配置文件。"
fi

# 拷贝 Playwright 内核 (可选，防止目标机器无法下载)
if [ -d "$HOME/.cache/ms-playwright" ]; then
    cp -r "$HOME/.cache/ms-playwright"/* "$PORTABLE_DIR/data/pw-browsers/" 2>/dev/null || true
fi

# 5. 动态生成核心运行脚本 openclaw.sh
echo "📜 [4/7] 正在动态生成运行隔离脚本 (openclaw.sh)..."
cat << 'EOF' > "$PORTABLE_DIR/openclaw.sh"
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ENV_FILE="$DIR/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

export PATH="$DIR/bin:$DIR/global-bin:$PATH"
export NODE_PATH="$DIR/lib/node_modules"
export PLAYWRIGHT_BROWSERS_PATH="$DIR/data/pw-browsers"

export HOME="$DIR/data/home"
export XDG_CONFIG_HOME="$DIR/data/home/.config"
export XDG_DATA_HOME="$DIR/data/home/.local/share"
export XDG_CACHE_HOME="$DIR/data/home/.cache"
export OPENCLAW_DIR="$DIR/data/home/.openclaw"

exec node "$DIR/global-bin/openclaw" "$@"
EOF
chmod +x "$PORTABLE_DIR/openclaw.sh"

# 6. 拷贝外部的运维管理脚本
echo "📜 [5/7] 正在将外部管理脚本集成至包内..."
for script in config.sh start.sh stop.sh; do
    if [ -f "$script" ]; then
        cp "$script" "$PORTABLE_DIR/"
        sed -i 's/\r$//' "$PORTABLE_DIR/$script"
        chmod +x "$PORTABLE_DIR/$script"
        echo "   -> 成功集成 $script"
    else
        echo "❌ 致命错误: 在当前目录下找不到 $script，打包中断！"
        echo "💡 提示: 请确保 config.sh, start.sh, stop.sh 都与 build_portable.sh 放在同一目录。"
        exit 1
    fi
done

# 7. 执行出厂默认配置初始化
echo "🛠️  [6/7] 正在执行出厂初始化，擦除隐私数据并注入占位符..."
"$PORTABLE_DIR/config.sh" --default

# 8. 打包成最终的压缩包
echo "🗜️  [7/7] 正在打包为 tar.gz..."
tar -czf "${PORTABLE_DIR}.tar.gz" "$PORTABLE_DIR"

echo "=================================================="
echo "🎉 批量部署绿色工程打包完成！"
echo "📦 最终分发包: ${PORTABLE_DIR}.tar.gz"
echo "=================================================="
