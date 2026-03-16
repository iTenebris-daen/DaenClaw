#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 动态计算当前的 OpenClaw 数据目录绝对路径
export OPENCLAW_DIR="$DIR/data/home/.openclaw"
export CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 错误: 找不到配置文件: $CONFIG_FILE"
    echo "请确保 OpenClaw 已经运行过一次或者手动放入了基础配置文件。"
    exit 1
fi

NODE_BIN="$DIR/bin/node"
if [ ! -f "$NODE_BIN" ]; then
    NODE_BIN="node"
fi

# ====================================================
# 1. 参数判断：是否为默认初始化模式
# ====================================================
if [ "$1" == "--default" ]; then
    echo "🔄 [静默模式] 正在将配置项重置为默认名称占位符，并修复硬编码路径..."
    export IS_DEFAULT="true"
    export INPUT_FEISHU_APP_ID="FEISHU_APP_ID"
    export INPUT_FEISHU_APP_SECRET="FEISHU_APP_SECRET"
    export AI_CHOICE="1" # 默认使用 vLLM 结构作为底座
    export INPUT_VLLM_BASE_URL="VLLM_BASE_URL"
    export INPUT_VLLM_API_KEY="VLLM_API_KEY"
    export INPUT_VLLM_MODEL="VLLM_MODEL"

else
    export IS_DEFAULT="false"
    # ====================================================
    # 2. 交互式界面 (正常运行模式)
    # ====================================================
    eval $("$NODE_BIN" -e "
    const fs = require('fs');
    try {
        const config = JSON.parse(fs.readFileSync(process.env.CONFIG_FILE, 'utf8'));
        const feishu = (config.channels && config.channels.feishu) ? config.channels.feishu : {};
        const vllm = (config.models && config.models.providers && config.models.providers.vllm) ? config.models.providers.vllm : {};
        const vllmModel = (vllm.models && vllm.models.length > 0) ? vllm.models[0] : {};
        const moonshot = (config.models && config.models.providers && config.models.providers.moonshot) ? config.models.providers.moonshot : {};

        console.log('CUR_FEISHU_APP_ID=\"' + (feishu.appId || '未配置') + '\"');
        console.log('CUR_FEISHU_APP_SECRET=\"' + (feishu.appSecret || '未配置') + '\"');
        console.log('CUR_VLLM_BASE_URL=\"' + (vllm.baseUrl || '未配置') + '\"');
        console.log('CUR_VLLM_API_KEY=\"' + (vllm.apiKey || '未配置') + '\"');
        console.log('CUR_VLLM_MODEL=\"' + (vllmModel.name || vllmModel.id || '未配置') + '\"');
        console.log('CUR_KIMI_API_KEY=\"' + (moonshot.apiKey || '未配置') + '\"');
    } catch (e) {
        console.log('CUR_FEISHU_APP_ID=\"读取失败\"');
    }
    ")

    echo "===================================================="
    echo "         OpenClaw 绿色版 - 快速引导配置"
    echo "  (直接回车代表跳过该项，保留现有配置/默认配置)"
    echo "===================================================="

    echo "【第一部分：通讯渠道配置】"
    read -p "1. 飞书 App ID [当前: $CUR_FEISHU_APP_ID]: " INPUT_FEISHU_APP_ID
    read -p "2. 飞书 App Secret [当前: $CUR_FEISHU_APP_SECRET]: " INPUT_FEISHU_APP_SECRET
    echo ""

    echo "【第二部分：AI 模型配置 (互斥单选)】"
    echo "请选择你要启用/配置的 AI 服务引擎："
    echo "  1) vLLM (本地私有化部署 - 需配置URL和模型名)"
    echo "  2) Moonshot Kimi (线上云端服务 - 仅需API Key)"
    echo "  0) 跳过不修改"
    read -p "请输入序号 [0/1/2]: " AI_CHOICE

    export INPUT_FEISHU_APP_ID INPUT_FEISHU_APP_SECRET AI_CHOICE

    if [ "$AI_CHOICE" == "1" ]; then
        echo "--- 正在配置 vLLM ---"
        read -p "  > vLLM Base URL [当前: $CUR_VLLM_BASE_URL]: " INPUT_VLLM_BASE_URL
        read -p "  > vLLM API Key [当前: $CUR_VLLM_API_KEY]: " INPUT_VLLM_API_KEY
        read -p "  > vLLM 模型名称 [当前: $CUR_VLLM_MODEL]: " INPUT_VLLM_MODEL
        export INPUT_VLLM_BASE_URL INPUT_VLLM_API_KEY INPUT_VLLM_MODEL
    elif [ "$AI_CHOICE" == "2" ]; then
        echo "--- 正在配置 Moonshot (Kimi) ---"
        echo "💡 提示：将自动使用官方默认地址与 Kimi K2.5 模型。"
        read -p "  > Kimi API Key [当前: $CUR_KIMI_API_KEY]: " INPUT_KIMI_API_KEY
        export INPUT_KIMI_API_KEY
    fi
fi

echo "----------------------------------------------------"
if [ "$IS_DEFAULT" != "true" ]; then echo "⚙️ 正在检查、更新配置并自适应修复绝对路径..."; fi

# ====================================================
# 3. 将新的配置写入 JSON (注入了路径自愈与环境清理逻辑)
# ====================================================
"$NODE_BIN" -e "
const fs = require('fs');
const file = process.env.CONFIG_FILE;
const openclawDir = process.env.OPENCLAW_DIR;
const aiChoice = process.env.AI_CHOICE;
const isDefault = process.env.IS_DEFAULT === 'true';

try {
    let config = JSON.parse(fs.readFileSync(file, 'utf8'));

    // ================== 核心清理与修复 ==================
    // 1. 仅在打包出厂(--default)时，彻底删除硬编码的 env 字段
    if (isDefault) {
        delete config.env;
    }

    // 2. 修复 workspace 路径
    if (!config.agents) config.agents = {};
    if (!config.agents.defaults) config.agents.defaults = {};
    config.agents.defaults.workspace = openclawDir + '/workspace';

    // 3. 修复 feishu 插件的安装路径
    if (config.plugins && config.plugins.installs && config.plugins.installs.feishu) {
        config.plugins.installs.feishu.installPath = openclawDir + '/extensions/feishu';
    }
    // ======================================================

    // --- 1. 更新飞书配置 ---
    if (process.env.INPUT_FEISHU_APP_ID || process.env.INPUT_FEISHU_APP_SECRET) {
        if (!config.channels) config.channels = {};
        if (!config.channels.feishu) config.channels.feishu = {};
        if (process.env.INPUT_FEISHU_APP_ID) config.channels.feishu.appId = process.env.INPUT_FEISHU_APP_ID;
        if (process.env.INPUT_FEISHU_APP_SECRET) config.channels.feishu.appSecret = process.env.INPUT_FEISHU_APP_SECRET;
    }

    // --- 2. 互斥更新模型配置 ---
    if (aiChoice === '1' || aiChoice === '2') {
        if (!config.models) config.models = { providers: {} };
        if (!config.models.providers) config.models.providers = {};
        if (!config.agents.defaults.model) config.agents.defaults.model = {};

        if (aiChoice === '1') {
            delete config.models.providers.moonshot;
            if (!config.models.providers.vllm) {
                config.models.providers.vllm = {
                    baseUrl: '', apiKey: '', api: 'openai-completions',
                    models: [{
                        id: '', name: '', reasoning: false, input: ['text'],
                        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                        contextWindow: 128000, maxTokens: 8192
                    }]
                };
            }
            let vllm = config.models.providers.vllm;
            if (process.env.INPUT_VLLM_BASE_URL) vllm.baseUrl = process.env.INPUT_VLLM_BASE_URL;
            if (process.env.INPUT_VLLM_API_KEY) vllm.apiKey = process.env.INPUT_VLLM_API_KEY;

            if (process.env.INPUT_VLLM_MODEL) {
                if (!vllm.models || vllm.models.length === 0) vllm.models = [{}];
                vllm.models[0].id = process.env.INPUT_VLLM_MODEL;
                vllm.models[0].name = process.env.INPUT_VLLM_MODEL;
            }
            config.agents.defaults.model.primary = 'vllm/' + (vllm.models[0].id || '');

        } else if (aiChoice === '2') {
            delete config.models.providers.vllm;
            if (!config.models.providers.moonshot) {
                config.models.providers.moonshot = {
                    baseUrl: 'https://api.moonshot.cn/v1', api: 'openai-completions',
                    models: [{
                        id: 'kimi-k2.5', name: 'Kimi K2.5', reasoning: false, input: ['text', 'image'],
                        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                        contextWindow: 256000, maxTokens: 8192, api: 'openai-completions'
                    }], apiKey: ''
                };
            }
            let moonshot = config.models.providers.moonshot;
            if (process.env.INPUT_KIMI_API_KEY) moonshot.apiKey = process.env.INPUT_KIMI_API_KEY;
            config.agents.defaults.model.primary = 'moonshot/kimi-k2.5';
        }
    }

    fs.writeFileSync(file, JSON.stringify(config, null, 2));
    if (!isDefault) console.log('✅ 配置文件已成功更新！');

} catch (e) {
    console.error('❌ 配置更新失败:', e.message);
    process.exit(1);
}
"

if [ "$IS_DEFAULT" != "true" ]; then
    echo "===================================================="
    echo "🎉 配置向导完成！"
    echo "⚠️ 重要提示：如果你已经启动了 OpenClaw，新配置需要重启服务才能生效。"
    echo "   请依次执行以下命令完成重启："
    echo "   ./stop.sh"
    echo "   ./start.sh"
    echo "===================================================="
else
    echo "✅ 默认占位符模板及环境自适应清理已成功执行！"
fi
