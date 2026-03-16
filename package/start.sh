#!/bin/bash
# 获取当前脚本所在绝对路径
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PID_FILE="$DIR/.openclaw.pid"
LOG_FILE="$DIR/openclaw.log"

# 1. 检查是否已经有实例在运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    # kill -0 只是检查进程是否存在，不会真的杀进程
    if kill -0 $PID 2>/dev/null; then
        echo "⚠️ OpenClaw Gateway 已经在运行中 (PID: $PID)！"
        echo "💡 如果想重新启动，请先运行 ./stop.sh"
        exit 1
    else
        echo "🧹 发现残留的 PID 文件，但进程已不存在，清理旧状态..."
        rm -f "$PID_FILE"
    fi
fi

# 2. 后台启动进程
echo "🚀 正在后台启动 OpenClaw Gateway..."
# 使用 nohup 保证退出终端后继续运行，将输出重定向到日志文件
nohup "$DIR/openclaw.sh" gateway > "$LOG_FILE" 2>&1 &
NEW_PID=$!

# 3. 记录新的 PID
echo $NEW_PID > "$PID_FILE"

echo "✅ 启动成功！实例运行在后台 (PID: $NEW_PID)"
echo "📄 运行日志将输出至: $LOG_FILE"
echo "🔍 你可以使用命令 'tail -f openclaw.log' 实时查看运行日志。"
