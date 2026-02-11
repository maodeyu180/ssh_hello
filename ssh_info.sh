#!/bin/bash

# --- 检查并安装 figlet ---
# 检测是否是 root 用户（兼容无 EUID 的 shell）
IS_ROOT=0
if [ "${EUID:-$(id -u 2>/dev/null)}" -eq 0 ] 2>/dev/null; then
  IS_ROOT=1
fi

SUDO_CMD=""
if [ "$IS_ROOT" -ne 1 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
  else
    echo "警告: 当前非 root 用户且未找到 sudo 命令，无法自动安装依赖。"
  fi
fi

if ! command -v figlet >/dev/null 2>&1; then
    echo "正在检测 figlet..."
    if [ "$IS_ROOT" -ne 1 ] && [ -z "$SUDO_CMD" ]; then
        echo "未找到 figlet，且无 sudo 权限，跳过自动安装。将回退到普通文本显示。"
    else
        if [ -x "$(command -v apt-get)" ]; then
            $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y figlet
        elif [ -x "$(command -v yum)" ]; then
            $SUDO_CMD yum install -y figlet
        elif [ -x "$(command -v dnf)" ]; then
            $SUDO_CMD dnf install -y figlet
        elif [ -x "$(command -v pacman)" ]; then
            $SUDO_CMD pacman -S --noconfirm figlet
        else
            echo "未找到 figlet，且无法自动安装。将回退到普通文本显示。"
        fi
    fi
fi

# --- 获取用户输入 ---
echo "=================================================="
read -p "请输入要生成的艺术字文本 (默认: $(hostname)): " BANNER_TEXT
BANNER_TEXT=${BANNER_TEXT:-$(hostname)}

echo "--------------------------------------------------"
echo "请选择艺术字颜色:"
echo "1. 红色"
echo "2. 绿色"
echo "3. 黄色"
echo "4. 蓝色"
echo "5. 紫色"
echo "6. 青色"
echo "7. 白色"
read -p "请输入颜色编号 (默认: 5): " COLOR_CHOICE

case $COLOR_CHOICE in
    1) COLOR_CODE="31";;
    2) COLOR_CODE="32";;
    3) COLOR_CODE="33";;
    4) COLOR_CODE="34";;
    5) COLOR_CODE="35";;
    6) COLOR_CODE="36";;
    7) COLOR_CODE="37";;
    *) COLOR_CODE="35";;
esac
echo "=================================================="

# --- 生成 ASCII 艺术字 ---
if command -v figlet &> /dev/null; then
    # 使用 sed 添加缩进以匹配原格式
    ASCII_ART=$(figlet -f standard "$BANNER_TEXT" | sed 's/^/            /')
else
    # figlet 未安装，使用普通文本
    ASCII_ART="            $BANNER_TEXT"
fi

echo "正在生成 ssh_hello 文件..."
rm -rf /etc/profile.d/ssh_hello.sh



# --- 写入脚本 Part 1 (头部逻辑) ---
cat << 'EOF' > /etc/profile.d/ssh_hello.sh
if [ -n "$SSH_CONNECTION" ]; then
    warning=$(if [ "$(df -m / | grep -v File | awk '{print $4}')" == "0" ];then echo " 警告，存储空间已满，请立即检查和处置！";fi)

    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n 1)
    IP=$(ip addr show $INTERFACE | grep '\<inet\>' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | awk 'NR==1')
    IPV6=$(ip addr show $INTERFACE | grep '\<inet6\>' | awk '{print $2}' | cut -d/ -f1 | awk 'NR==1')

    # IPv6 判空处理
    if [ -z "$IPV6" ]; then
        IP_DISPLAY="$IP"
    else
        IP_DISPLAY="$IP / $IPV6"
    fi

    # 当前连接的 IP 地址
    CURRENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')

    # 上次连接信息（兼容不同 last 选项）
    LAST_CMD="last -i"
    if last -Fi >/dev/null 2>&1; then
        LAST_CMD="last -Fi"
    fi

    LAST_INFO=$($LAST_CMD "$USER" 2>/dev/null | grep "pts/" | head -2 | tail -1)
    if [ -z "$LAST_INFO" ]; then
        LAST_INFO=$($LAST_CMD 2>/dev/null | grep "pts/" | head -2 | tail -1)
    fi
    LAST_IP="无记录"
    LAST_TIME="无记录"
    LAST_LOGIN_EPOCH=""

    if [ -n "$LAST_INFO" ]; then
        LAST_IP=$(echo $LAST_INFO | awk '{print $3}')
        LAST_TIME=$(echo $LAST_INFO | awk '{for(i=4;i<=NF-1;i++) printf $i" "; print $(NF)}')
        # 计算上次登录时间戳（用于失败次数统计）
        LAST_LOGIN_STR=$(echo "$LAST_INFO" | awk '{print $4,$5,$6,$7,$8}')
        LAST_LOGIN_EPOCH=$(date -d "$LAST_LOGIN_STR" +%s 2>/dev/null)
        if [ -z "$LAST_LOGIN_EPOCH" ]; then
            LAST_LOGIN_STR=$(echo "$LAST_INFO" | awk '{print $4,$5,$6,$7}')
            LAST_LOGIN_STR="$LAST_LOGIN_STR $(date +%Y)"
            LAST_LOGIN_EPOCH=$(date -d "$LAST_LOGIN_STR" +%s 2>/dev/null)
        fi
    fi

    # last 无记录时，回退到 auth.log / secure / journalctl
    if [ "$LAST_IP" = "无记录" ]; then
        LAST_LOG_LINE=""
        if [ -f "/var/log/auth.log" ]; then
            LAST_LOG_LINE=$(grep "sshd" "/var/log/auth.log" | grep "Accepted" | grep "$USER" | tail -2 | head -1)
        elif [ -f "/var/log/secure" ]; then
            LAST_LOG_LINE=$(grep "sshd" "/var/log/secure" | grep "Accepted" | grep "$USER" | tail -2 | head -1)
        elif command -v journalctl >/dev/null 2>&1; then
            LAST_LOG_LINE=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service 2>/dev/null | grep "Accepted" | grep "$USER" | tail -2 | head -1)
        fi
        if [ -n "$LAST_LOG_LINE" ]; then
            LAST_IP=$(echo "$LAST_LOG_LINE" | awk '{for(i=1;i<=NF;i++) if($i=="from") {print $(i+1); exit}}')
            LAST_TIME=$(echo "$LAST_LOG_LINE" | awk '{print $1,$2,$3}')
            LAST_LOGIN_STR="$LAST_TIME $(date +%Y)"
            LAST_LOGIN_EPOCH=$(date -d "$LAST_LOGIN_STR" +%s 2>/dev/null)
            if [ -z "$LAST_LOGIN_EPOCH" ]; then
                LAST_LOGIN_EPOCH=$(date -d "$LAST_TIME" +%s 2>/dev/null)
            fi
        fi
    fi

    # 获取登录失败次数的通用函数
    get_failed_count() {
        local since_epoch="$1"
        local count="0"
        local log_file=""

        if command -v journalctl >/dev/null 2>&1; then
            local since_flag="--since=today"
            [ -n "$since_epoch" ] && since_flag="--since=@$since_epoch"
            count=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service $since_flag 2>/dev/null | grep -ci "failed.*password\|authentication.*failure")
            echo "${count:-0}"
            return
        fi

        if [ -f "/var/log/auth.log" ]; then
            log_file="/var/log/auth.log"
        elif [ -f "/var/log/secure" ]; then
            log_file="/var/log/secure"
        fi

        if [ -z "$log_file" ]; then
            echo "0"
            return
        fi

        if [ -z "$since_epoch" ]; then
            count=$(grep "sshd" "$log_file" | grep "Failed password" | wc -l)
            echo "${count:-0}"
            return
        fi

        if awk 'BEGIN{exit(mktime("2026 02 11 00 00 00")>0?0:1)}' >/dev/null 2>&1; then
            count=$(awk -v since="$since_epoch" '
                function mon2num(m){
                    return (m=="Jan")?1:(m=="Feb")?2:(m=="Mar")?3:(m=="Apr")?4:(m=="May")?5:(m=="Jun")?6:(m=="Jul")?7:(m=="Aug")?8:(m=="Sep")?9:(m=="Oct")?10:(m=="Nov")?11:(m=="Dec")?12:0
                }
                /sshd/ && /Failed password/ {
                    mon=mon2num($1); day=$2; split($3,t,":")
                    if (mon>0 && day>0) {
                        ts=mktime(sprintf("%d %d %d %d %d %d", strftime("%Y"), mon, day, t[1], t[2], t[3]))
                        if (ts >= since) c++
                    }
                }
                END{print c+0}
            ' "$log_file")
        else
            count=$(grep "sshd" "$log_file" | grep "Failed password" | while read -r mon day time rest; do
                ts=$(date -d "$mon $day $time $(date +%Y)" +%s 2>/dev/null || echo 0)
                if [ "$ts" -ge "$since_epoch" ] 2>/dev/null; then
                    echo 1
                fi
            done | wc -l)
        fi

        echo "${count:-0}"
    }

    FAILED_SINCE_LAST=$(get_failed_count "$LAST_LOGIN_EPOCH")

    CURRENT_SSH_CONNECTIONS=$(who | grep 'pts/' | wc -l)

    # 系统负载
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')

    # CPU 使用率（通过解析 idle 值计算，兼容不同 top 版本）
    CPU_IDLE=$(top -bn1 2>/dev/null | grep -i 'cpu' | head -1 | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /id/) {gsub(/[^0-9.]/,"",$i); print $i}}')
    if [ -n "$CPU_IDLE" ]; then
        CPU_USAGE=$(awk "BEGIN {printf \"%.1f%%\", 100 - $CPU_IDLE}")
    else
        CPU_USAGE="无法获取"
    fi

    # 登录时间
    LOGIN_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    # 主机名
    HOST_NAME=$(hostname)

    # 进程数（兼容写法，跳过表头）
    PROCESS_COUNT=$(ps -e 2>/dev/null | tail -n +2 | wc -l)

    # Swap 使用（未启用时显示"未启用"）
    SWAP_INFO=$(free -m | grep Swap | awk '{if($2==0) print "未启用"; else {a=$3*100/$2; printf("%.1f%s %dM/%dM\n",a,"%",$3,$2)}}')
    if [ -z "$SWAP_INFO" ]; then
        SWAP_INFO="无法获取"
    fi

    clear
    echo -e "
EOF

# --- 写入脚本 Part 2 (动态生成的艺术字) ---
# 注意：这里使用追加模式 (>>)，并处理颜色代码
echo "    \e[${COLOR_CODE}m" >> /etc/profile.d/ssh_hello.sh
# 使用 printf 确保反斜杠等字符原样输出
printf "%s\n" "$ASCII_ART" >> /etc/profile.d/ssh_hello.sh
echo "    \e[0m" >> /etc/profile.d/ssh_hello.sh

# --- 写入脚本 Part 3 (剩余部分) ---
cat << 'EOF' >> /etc/profile.d/ssh_hello.sh


        主 机 名 : $HOST_NAME
        登录时间 : $LOGIN_TIME
        CPU 信息 : $(cat /proc/cpuinfo | grep 'processor' | sort | uniq | wc -l)核处理器 | $(uname -p)架构
        系统版本 : $(awk -F '[= \"]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release) | $(uname -r)-$(getconf LONG_BIT)
        系统负载 : $LOAD_AVG (1/5/15min)
        CPU 占用 : $CPU_USAGE
        可用存储 : $(df -m / | grep -v File | awk '{a=$4*100/$2;b=$4} {printf("%.1f%s %.1fM\n",a,"%",b)}') ${warning}
        可用内存 : $(free -m | grep Mem | awk '{a=$7*100/$2;b=$7} {printf("%.1f%s %.1fM\n",a,"%",b)}')
        交换内存 : $SWAP_INFO
        进 程 数 : $PROCESS_COUNT
        运行时间 : $(awk '{a=int($1/86400);b=int(($1%86400)/3600);c=int(($1%3600)/60);d=int($1%60)} {printf("%d天 %d小时 %d分钟 %d秒\n",a,b,c,d)}' /proc/uptime)
        设备 IP  : $IP_DISPLAY
        本次 IP  : $CURRENT_IP
        上次 IP  : $LAST_IP
        上次登录 : $LAST_TIME
        SSH 连接 : $CURRENT_SSH_CONNECTIONS
        失败次数 : $FAILED_SINCE_LAST
    "
fi
EOF

echo "授予ssh_hello 可执行权限"
chmod 744 /etc/profile.d/ssh_hello.sh

echo "生成完成！请重新连接 SSH 查看效果。"
