#!/bin/bash
# 获取当前脚本所在绝对路径
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PID_FILE="$DIR/.openclaw.pid"

# 1. 检查 PID 文件是否存在
if [ ! -f "$PID_FILE" ]; then
    echo "⚠️ 未发现运行状态文件 ($PID_FILE)。"
    echo "💡 OpenClaw Gateway 当前可能并未运行。"
    exit 0
fi

PID=$(cat "$PID_FILE")

# 2. 检查进程是否真实存在并执行停止操作
if kill -0 $PID 2>/dev/null; then
    echo "🛑 正在停止 OpenClaw Gateway (PID: $PID)..."

    # 发送正常的终止信号 (SIGTERM)
    kill $PID

    # 等待进程优雅退出 (最多等10秒)
    for i in {1..10}; do
        if kill -0 $PID 2>/dev/null; then
            sleep 1
        else
            break
        fi
    done

    # 如果10秒后还在运行，就强制杀掉 (SIGKILL)
    if kill -0 $PID 2>/dev/null; then
        echo "⚠️ 进程未能按时退出，正在强制结束..."
        kill -9 $PID
    fi

    echo "✅ 停止成功！"
else
    echo "⚠️ 进程 (PID: $PID) 已经不在运行中。"
fi

# 3. 清理 PID 文件
rm -f "$PID_FILE"
