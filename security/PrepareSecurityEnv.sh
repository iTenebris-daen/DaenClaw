#!/bin/bash
###
### Usage:
###   This script for Ubuntu security reinforce !
###   eg: sudo bash SecurityReinforce.sh run
###
### Options:
###   run        Execute this script.
###   -h         Show this message.
### Action:
###   This script will create the default user 'daenclaw' and password are 'DC@DaenSample2026'

help() {
        awk -F'### ' '/^###/ { print $2 }' "$0"
}

if [[ $# == 0 ]] || [[ "$1" == "-h" ]]; then
        help
        exit 1
fi

if [[ "$1" == "run" ]]; then
rq=$(date +%Y%m%d)
w_user_list="root daenclaw"
b_user_list="games gnats irc list news uucp"
b_user_group="games gnats irc list news uucp"

lockUser(){
   user=$1
   for usr in $user;do
       if [[ $w_user_list =~ $usr ]];then
          echo "Default or system user ($usr), Nothing to do !"
       else
          echo "Locking the password for the $usr account"
          usermod "$usr" -s /usr/sbin/nologin
       fi
   done
}

# 判断是否 root 用户运行
if [ "$USER" != "root" ];then
   echo "❌ Sorry! Only root can run me ! Please use sudo."
   exit 1
fi

echo "🚀 开始执行 Ubuntu 系统加固..."

# 检测空密码用户
nonePass=$(awk -F: '($2==""){print $1}' /etc/shadow)
if [[ -z $nonePass ]];then
   echo "✅ Check OS user password successful !"
else
   lockUser "$nonePass"
fi

# 检测除 root 外的其他 UID 为 0 的特权用户
rootUser=$(awk -F: '($3==0 && $1!="root"){print $1}' /etc/passwd)
if [[ -z $rootUser ]];then
   echo "✅ Check OS user of root successful !"
else
   lockUser "$rootUser"
fi

# 删除默认系统不必要用户
for u in $b_user_list;do
    if id "$u" &>/dev/null; then
        echo "Remove $u by OS default account !"
        userdel -r "$u" 2>/dev/null || true
    fi
done

# 删除默认系统不必要属组
for gr in $b_user_group;do
    if getent group "$gr" &>/dev/null; then
        echo "Remove $gr by OS default group !"
        groupdel "$gr" 2>/dev/null || true
    fi
done

# 修改密码策略
# echo "🔧 修改密码过期策略..."
# cp /etc/login.defs /etc/login.defs.bak$rq
# sed -i 's/^\(PASS_MIN_LEN\).*/\1    12/g' /etc/login.defs
# sed -i 's/^\(PASS_MAX_DAYS\).*/\1   90/g' /etc/login.defs

# Ubuntu 需要安装 libpam-pwquality 来支持复杂度和防爆破
export DEBIAN_FRONTEND=noninteractive
systemctl stop unattended-upgrades
apt-get update -qq
if ! apt-get install -y libpam-pwquality -qq; then
    echo "❌ 错误：libpam-pwquality 安装失败，请检查网络或软件源配置"
    exit 1
fi

# 修改密码复杂度 (Ubuntu 推荐修改 /etc/security/pwquality.conf)
echo "🔧 修改密码复杂度限制..."
echo "   - 密码最小长度：12 个字符"
echo "   - 至少包含 1 个数字"
echo "   - 至少包含 1 个大写字母"
echo "   - 至少包含 1 个小写字母"
echo "   - 至少包含 1 个特殊字符"
echo "   - 新旧密码至少 5 个字符不同"
echo "   - 对 root 用户也强制执行"
cp /etc/security/pwquality.conf /etc/security/pwquality.conf.bak$rq
cat > /etc/security/pwquality.conf <<EOF
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
difok = 5
enforce_for_root
EOF

# 口令重复次数限制 (Ubuntu 修改 common-password)
echo "🔧 增加口令重复次数限制..."
cp /etc/pam.d/common-password /etc/pam.d/common-password.bak$rq
if ! grep -q "pam_pwhistory.so" /etc/pam.d/common-password; then
   sed -i '/pam_unix.so/ s/$/ remember=5/' /etc/pam.d/common-password
fi

# 账号锁定策略 (终端登录失败 5 次，锁定 10 分钟)
# Ubuntu 22.04+ 原生支持 faillock，只需修改 /etc/security/faillock.conf
echo "🔧 配置账号锁定防爆破策略..."
cp /etc/security/faillock.conf /etc/security/faillock.conf.bak$rq
cat > /etc/security/faillock.conf <<EOF
dir = /var/log/faillock
audit
silent
deny = 5
unlock_time = 600
even_deny_root
root_unlock_time = 600
EOF
pam-auth-update --enable faillock

# 修改会话超时时间以及目录权限
echo "🔧 修改会话超时时间与默认权限"
cp /etc/profile /etc/profile.bak$rq
if ! grep -q "export TMOUT=600" /etc/profile; then
   echo 'export TMOUT=600' >> /etc/profile
   echo 'readonly TMOUT' >> /etc/profile
fi
if ! grep -q "umask 027" /etc/profile; then
   echo 'umask 027' >> /etc/profile
fi

# 禁止 root 用户远程登录
echo "🔧 配置 SSH 安全..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak$rq
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config

# 配置用户最小授权
echo "🔧 限制关键文件权限..."
chmod 644 /etc/passwd
chmod 400 /etc/shadow
chmod 644 /etc/group
chmod 644 /etc/services
chmod 600 /etc/security

# 设置关键文件的属性 (Ubuntu 的核心日志是 syslog 和 auth.log)
echo "🔧 为核心日志添加防篡改属性..."
touch /var/log/syslog /var/log/auth.log
chattr +a /var/log/syslog
chattr +a /var/log/auth.log

# 增加 banner 声明
echo "🔧 增加登录警告 Banner..."
if ! grep -q "^Banner /etc/motd" /etc/ssh/sshd_config; then
   sed -i '/^#Banner none/a\Banner /etc/motd' /etc/ssh/sshd_config
fi
cat > /etc/motd <<EOF
*********************************************************
*** WARNING ***
Authorised access only!
Disconnect IMMEDIATELY if you are not an authorized user!
Your IP has been recorded. Don't damage any files!
*********************************************************
EOF

# 禁用 Ctrl+Alt+Del 重启系统 (Ubuntu 标准做法)
echo "🔧 禁用 Ctrl+Alt+Del 重启"
systemctl mask ctrl-alt-del.target

# 日志文件安全配置
echo "🔧 调整日志文件权限..."
chmod 640 /var/log/syslog 2>/dev/null || true
chmod 640 /var/log/auth.log 2>/dev/null || true
chmod 640 /var/log/kern.log 2>/dev/null || true
chmod 640 /var/log/cron.log 2>/dev/null || true

# 禁用非必要服务 (加入 || true 防止未安装报错)
echo "🔧 关闭非必要服务..."
for svc in postfix rpcbind cups avahi-daemon dnsmasq; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

# PAM认证，禁止 sudo 组之外的用户使用 su 切换到 root
echo "🔧 限制 su 命令使用..."
cp /etc/pam.d/su /etc/pam.d/su.bak$rq
# Ubuntu 中管理员组是 sudo 而不是 wheel
sed -i 's/^# auth       required   pam_wheel.so.*/auth       required   pam_wheel.so group=sudo/g' /etc/pam.d/su

# 禁用 IP 源路由及禁止路由转发
echo "🔧 配置内核网络安全策略..."
cp /etc/sysctl.conf /etc/sysctl.conf.bak$rq
cat >> /etc/sysctl.conf <<EOF
# 禁用包转发
net.ipv4.ip_forward=0
# 禁用 IP 源路由
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
EOF
sysctl -p /etc/sysctl.conf &>/dev/null

# 隐藏系统版本
mv /etc/issue /etc/issue.bak$rq 2>/dev/null || true
mv /etc/issue.net /etc/issue.net.bak$rq 2>/dev/null || true

# 创建 daenclaw 运维用户 (加入 sudo 组)
if ! id "daenclaw" &>/dev/null; then
    echo "👤 创建 daenclaw 运维用户..."
    useradd daenclaw -m -s /bin/bash
    echo "daenclaw:DC@DaenSample2026" | chpasswd
    usermod -aG sudo daenclaw
else
    echo "👤 用户 daenclaw 已存在，跳过创建。"
fi

echo "🔄 重启相关服务以生效配置..."
systemctl restart sshd.service
systemctl restart rsyslog.service 2>/dev/null || true

echo "======================================================="
echo "🎉 Run Ubuntu Security Reinforce Script Successful !"
echo "⚠️  注意: root 远程登录已关闭，请确保新用户 daenclaw 可以正常登录。"
echo "======================================================="
fi
