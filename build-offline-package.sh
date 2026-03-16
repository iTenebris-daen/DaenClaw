#!/bin/bash
# build-offline-package.sh - OpenClaw 离线安装包生成脚本
# 生成的包可在无网络 Linux 机器上一键安装，完全复刻当前环境

set -e

# === 配置区 ===
PKG_NAME="openclaw-offline-linux-x64"
PKG_VERSION="2026.03.12"
OUTPUT_DIR="/tmp/openclaw-offline-pkg"
BUILD_DIR="${OUTPUT_DIR}/${PKG_NAME}"
NODE_VERSION="v24.14.0"
NODE_ARCH="x64"
NODE_DIST_URL="https://nodejs.org/dist/${NODE_VERSION}"
NPMMIRROR="https://registry.npmmirror.com"

# === 环境检测 ===
echo "🌱 OpenClaw 离线包生成器 v${PKG_VERSION}"
echo "📦 目标平台: Linux x64"
echo "🔧 Node.js 版本: ${NODE_VERSION}"

if [ ! -f /usr/local/bin/playwright ]; then
    echo "❌ 错误: 未找到 playwright CLI，请先运行 'npm install -g playwright'"
    exit 1
fi

# === 清理旧包 ===
rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}"
echo "📁 创建工作目录: ${BUILD_DIR}"

# === 1. 打包 Node.js 静态二进制 ===
echo "📦 正在下载 Node.js ${NODE_VERSION} 静态二进制..."
NODE_TARBALL="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
NODE_URL="${NODE_DIST_URL}/${NODE_TARBALL}"
NODE_LOCAL="${BUILD_DIR}/${NODE_TARBALL}"

# 优先从当前环境复制（如果存在）
if [ -f "/usr/local/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" ]; then
    cp "/usr/local/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" "${NODE_LOCAL}"
    echo "✅ 复制本地 Node.js 包"
elif curl -sfL "${NODE_URL}" -o "${NODE_LOCAL}"; then
    echo "✅ 下载 Node.js 包完成"
else
    echo "❌ 下载 Node.js 失败: ${NODE_URL}"
    echo "💡 提示: 如果网络受限，可手动下载后放入 ${BUILD_DIR}，再重新运行此脚本"
    exit 1
fi

# === 2. 打包 npm 全局模块 ===
echo "📦 正在打包 npm 全局模块..."
NPM_CACHE_DIR="${BUILD_DIR}/npm-cache"
NPM_GLOBAL_DIR="${BUILD_DIR}/npm-global"
mkdir -p "${NPM_CACHE_DIR}" "${NPM_GLOBAL_DIR}"

# 导出已安装的 npm 包列表（兼容无 jq 环境）
echo "list npm global packages..."
npm ls -g --depth=0 2>/dev/null | grep -E '^[^ ]' | sed 's/@.*//' | grep -v npm > "${BUILD_DIR}/npm-packages.txt" || true

# 手动打包 openclaw, playwright, agent-browser
for PKG in openclaw playwright agent-browser; do
    echo "📦 打包 ${PKG}..."
    PKG_PATH=$(npm root -g)/${PKG}
    if [ -d "${PKG_PATH}" ]; then
        # 复制模块源码
        cp -r "${PKG_PATH}" "${NPM_GLOBAL_DIR}/"
        # 生成 package-lock（简化版）
        if [ -f "${PKG_PATH}/package.json" ]; then
            cd "${PKG_PATH}" && npm pack --pack-destination="${NPM_CACHE_DIR}" 2>/dev/null || true
        fi
    else
        echo "⚠️  警告: ${PKG} 模块未找到，跳过"
    fi
done

# === 3. 打包 Playwright 浏览器离线安装包 ===
echo "📦 正在生成 Playwright 浏览器离线安装脚本..."

cat > "${BUILD_DIR}/install-browsers.sh" << 'EOF'
#!/bin/bash
# Playwright 浏览器离线安装脚本
set -e

echo "Install Playwright browsers (offline mode)..."

# 安装 Chromium（openclaw browser 技能依赖）
echo " Chromium..."
npx playwright install chromium --with-deps

# 安装 Firefox & WebKit（备用）
echo " Firefox..."
npx playwright install firefox --with-deps

echo " WebKit..."
npx playwright install webkit --with-deps

echo "✅ Playwright browsers installed"
EOF

chmod +x "${BUILD_DIR}/install-browsers.sh"

# === 4. 复制 OpenClaw 配置和 Workspace ===
echo "📋 正在复制 OpenClaw 配置..."

# 复制 openclaw.json 配置
if [ -f ~/.openclaw/openclaw.json ]; then
    mkdir -p "${BUILD_DIR}/config"
    cp ~/.openclaw/openclaw.json "${BUILD_DIR}/config/"
fi

# 复制 workspace 中的自定义技能
if [ -d ~/.openclaw/workspace/skills ]; then
    mkdir -p "${BUILD_DIR}/skills"
    cp -r ~/.openclaw/workspace/skills "${BUILD_DIR}/"
fi

# === 5. 生成安装脚本 ===
echo "🔧 生成 install.sh..."

cat > "${BUILD_DIR}/install.sh" << 'INSTALL_EOF'
#!/bin/bash
# install.sh - OpenClaw 离线安装脚本（Linux x64）

set -e

echo "🌱 OpenClaw 离线安装器"
echo "Platform: Linux x64"
echo "Version: ${PKG_VERSION}"
echo ""

# === 参数解析 ===
TARGET_DIR="/opt/openclaw"
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --target)
            TARGET_DIR="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "📁 安装目标路径: \${TARGET_DIR}"

# === 提前检测 ===
if ! command -v apt &> /dev/null; then
    echo "⚠️  非 Debian/Ubuntu 系统，依赖安装可能失败，请手动安装: curl, libasound2, libatk-bridge2.0-0, libcups2, libdrm2, libnss3, libxkbcommon0, libxcomposite1, libxdamage1, libxfixes3, libxrandr2, libgbm1"
fi

# === 1. 安装 Node.js ===
echo "📦 正在安装 Node.js..."
NODE_TARBALL="\$(find \$(dirname "\$0") -name 'node-*-linux-x64.tar.xz' | head -n1)"

if [ -z "\$NODE_TARBALL" ]; then
    echo "❌ 错误: 未找到 Node.js 包，安装终止"
    exit 1
fi

mkdir -p "\${TARGET_DIR}/node"
tar -xJf "\$NODE_TARBALL" -C "\${TARGET_DIR}/node" --strip-components=1

# 添加环境变量
echo "export PATH=\${TARGET_DIR}/node/bin:\$PATH" >> ~/.bashrc
export PATH="\${TARGET_DIR}/node/bin:\$PATH"

echo "✅ Node.js installed at: \${TARGET_DIR}/node"

# === 2. 安装 npm 全局包 ===
echo "📦 正在安装 npm 全局包..."

NPM_GLOBAL_DIR="\$(dirname "\$0")/npm-global"

if [ -d "\${NPM_GLOBAL_DIR}" ]; then
    # 重新安装 openclaw, playwright, agent-browser
    for PKG_DIR in "\${NPM_GLOBAL_DIR}"/*; do
        if [ -d "\${PKG_DIR}" ]; then
            PKG_NAME=\$(basename "\${PKG_DIR}")
            echo "  - \${PKG_NAME}..."
            cd "\${PKG_DIR}" && npm install -g . 2>/dev/null || true
        fi
    done
else
    echo "❌ 错误: 未找到 npm 全局包目录，安装终止"
    exit 1
fi

# === 3. 配置 npm 镜像 ===
echo "🔧 配置 npm 镜像..."
npm config set registry https://registry.npmmirror.com

# === 4. 配置 Playwright 浏览器 ===
echo "🔧 正在配置 Playwright 浏览器..."
PLAYWRIGHT_BROWSER_SCRIPT="\$(dirname "\$0")/install-browsers.sh"
if [ -f "\${PLAYWRIGHT_BROWSER_SCRIPT}" ]; then
    bash "\${PLAYWRIGHT_BROWSER_SCRIPT}"
else
    echo "⚠️  警告: Playwright 浏览器安装脚本未找到，手动运行 'npx playwright install chromium' 安装"
fi

# === 5. 恢复 OpenClaw 配置 ===
echo "📋 正在恢复配置..."
mkdir -p ~/.openclaw
if [ -d "\$(dirname "\$0")/config" ]; then
    cp -r "\$(dirname "\$0")/config/." ~/.openclaw/ 2>/dev/null || true
fi

if [ -d "\$(dirname "\$0")/skills" ]; then
    mkdir -p ~/.openclaw/workspace/skills
    cp -r "\$(dirname "\$0")/skills/." ~/.openclaw/workspace/skills/ 2>/dev/null || true
fi

# === 完成 ===
echo ""
echo "✅ OpenClaw 安装完成！"
echo ""
echo "💡 下一步操作:"
echo "  1. 重新打开终端，或运行: source ~/.bashrc"
echo "  2. 运行: openclaw onboard 初始化配置"
echo "  3. 运行: openclaw gateway start 启动服务"
INSTALL_EOF

chmod +x "${BUILD_DIR}/install.sh"

# === 6. 生成 README ===
cat > "${BUILD_DIR}/README.md" << README_EOF
# OpenClaw 离线安装包

- **版本**: v${PKG_VERSION}
- **平台**: Linux x64
- **Node.js**: ${NODE_VERSION}
- **生成时间**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## 安装步骤

1. 上传整个目录到目标机器
2. 执行: \`sudo ./install.sh\`
3. 安装完成后按提示初始化

## 注意事项

- 安装需要 \`sudo\` 权限（写入 \`/opt/openclaw\`)
- 目标机器需联网下载浏览器依赖（chromium/firefox/webkit 的系统依赖）
- 如果目标机器完全离线，需提前在本机运行 \`npx playwright install chromium --with-deps\` 并复制 \`~/.cache/ms-playwright\` 到目标机

## 包含内容

- \`node-v24.14.0-linux-x64.tar.xz\` — Node.js 静态二进制
- \`npm-global/\` — npm 全局模块（openclaw, playwright, agent-browser）
- \`npm-cache/\` — npm 包缓存（备用）
- \`config/\` — OpenClaw 配置（openclaw.json）
- \`skills/\` — 自定义技能（workspace/skills）
- \`install-browsers.sh\` — Playwright 浏览器安装脚本
- \`install.sh\` — 一键安装主脚本
README_EOF

# === 打包输出 ===
echo "📦 打包离线安装包..."
cd "${OUTPUT_DIR}"
tar -czf "${PKG_NAME}.tar.gz" "${PKG_NAME}"
echo "✅ 离线包生成完成: ${OUTPUT_DIR}/${PKG_NAME}.tar.gz"

# === 保留源目录（方便调试） ===
echo "📁 源目录保留: ${BUILD_DIR}"
echo "🌱 完成！"
