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
    echo "🔄 [静默模式] 正在执行出厂脱敏清理并注入默认占位符..."
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
# 3. 将新的配置写入 JSON (注入了脱敏、修复与无损注册逻辑)
# ====================================================
"$NODE_BIN" -e "
const fs = require('fs');
const crypto = require('crypto'); // 【增加1】: 引入内置加密模块
const file = process.env.CONFIG_FILE;
const openclawDir = process.env.OPENCLAW_DIR;
const aiChoice = process.env.AI_CHOICE;
const isDefault = process.env.IS_DEFAULT === 'true';

try {
    let config = JSON.parse(fs.readFileSync(file, 'utf8'));

    // ================== 核心清理与修复 ==================
    if (isDefault) {
        delete config.env;

        if (config.gateway && config.gateway.auth) {
            config.gateway.auth.token = 'GATEWAY_AUTH_TOKEN_PLACEHOLDER';
        }

        if (config.skills && config.skills.entries) {
            for (let skillName in config.skills.entries) {
                if (config.skills.entries[skillName].env) {
                    delete config.skills.entries[skillName].env;
                }
            }
        }

        if (config.tools && config.tools.web && config.tools.web.search && config.tools.web.search.apiKey) {
            config.tools.web.search.apiKey = 'WEB_SEARCH_API_KEY';
        }

        if (!config.agents) config.agents = {};
        if (!config.agents.defaults) config.agents.defaults = {};
        config.agents.defaults.workspace = '<OPENCLAW_DIR>/workspace';

        // 仅在出厂脱敏时，清空历史测试遗留的冗余模型和降级链
        if (!config.agents.defaults.model) config.agents.defaults.model = {};
        config.agents.defaults.model.fallbacks = [];
        config.agents.defaults.models = {};

        if (config.plugins && config.plugins.installs) {
            for (let pluginName in config.plugins.installs) {
                config.plugins.installs[pluginName].installPath = '<OPENCLAW_DIR>/extensions/' + pluginName;
            }
        }
    } else {
        // 【增加2】: 如果发现是出厂占位符，自动生成随机安全 Token
        if (config.gateway && config.gateway.auth && config.gateway.auth.token === 'GATEWAY_AUTH_TOKEN_PLACEHOLDER') {
            const newToken = crypto.randomBytes(24).toString('hex');
            config.gateway.auth.token = newToken;
            console.log('🔑 [安全] 已为您自动生成全新的 Gateway 管理 Token: ' + newToken);
            console.log('   (请妥善保管，如需查看可打开 openclaw.json 获取)');
        }

        if (!config.agents) config.agents = {};
        if (!config.agents.defaults) config.agents.defaults = {};
        config.agents.defaults.workspace = openclawDir + '/workspace';

        if (config.plugins && config.plugins.installs) {
            for (let pluginName in config.plugins.installs) {
                config.plugins.installs[pluginName].installPath = openclawDir + '/extensions/' + pluginName;
            }
        }
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
        if (!config.agents) config.agents = {};
        if (!config.agents.defaults) config.agents.defaults = {};
        if (!config.agents.defaults.model) config.agents.defaults.model = {};
        if (!config.agents.defaults.models) config.agents.defaults.models = {};

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

            // 动态注册 vLLM 主模型 (仅更新/插入，不破坏其他模型)
            const primaryId = 'vllm/' + (vllm.models[0].id || '');
            config.agents.defaults.model.primary = primaryId;
            if (!config.agents.defaults.models[primaryId]) {
                config.agents.defaults.models[primaryId] = {};
            }

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

            // 动态注册 Kimi 主模型并赋予别名 (仅更新/插入，不破坏其他模型)
            const primaryId = 'moonshot/kimi-k2.5';
            config.agents.defaults.model.primary = primaryId;
            if (!config.agents.defaults.models[primaryId]) {
                config.agents.defaults.models[primaryId] = { alias: 'Kimi' };
            } else if (!config.agents.defaults.models[primaryId].alias) {
                config.agents.defaults.models[primaryId].alias = 'Kimi';
            }
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

    # 【增加3】: 注册全局命令
    USER_BIN_DIR="$HOME/.local/bin"
    mkdir -p "$USER_BIN_DIR"
    ln -sf "$DIR/openclaw.sh" "$USER_BIN_DIR/openclaw"

    echo "🔗 已为您注册全局命令: openclaw"
    echo "   (软链接指向: $USER_BIN_DIR/openclaw)"

    if [[ ":$PATH:" != *":$USER_BIN_DIR:"* ]]; then
        echo "⚠️  注意: $USER_BIN_DIR 似乎不在您的 PATH 环境变量中。"
        echo "   为确保 'openclaw' 命令立即生效，您可以运行一次："
        echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    else
        echo "💡 您现在可以在终端任意位置直接输入 'openclaw' 来运行它了！"
    fi
    echo "----------------------------------------------------"

    echo "⚠️ 重要提示：如果您已经启动了 OpenClaw，新配置需要重启服务才能生效。"
    echo "   请依次执行以下命令完成重启："
    echo "   ./stop.sh"
    echo "   ./start.sh"
    echo "===================================================="
else
    echo "✅ 默认脱敏模板及占位符已成功写入！"
fi
