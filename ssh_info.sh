#!/bin/bash
echo "正在生成ssh_hello 文件"
rm -rf /etc/profile.d/ssh_hello.sh
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

    # 上次连接信息（兼容无 -i 参数的环境）
    LAST_INFO=$(last -i 2>/dev/null | grep "pts/" | head -2 | tail -1)
    if [ -z "$LAST_INFO" ]; then
        LAST_INFO=$(last 2>/dev/null | grep "pts/" | head -2 | tail -1)
    fi
    if [ -n "$LAST_INFO" ]; then
        LAST_IP=$(echo $LAST_INFO | awk '{print $3}')
        LAST_TIME=$(echo $LAST_INFO | awk '{for(i=4;i<=NF-1;i++) printf $i" "; print $(NF)}')
    else
        LAST_IP="无记录"
        LAST_TIME="无记录"
    fi

    # 获取登录失败次数的通用函数
    get_failed_count() {
        local since="$1"
        if [ -f "/var/log/auth.log" ]; then
            if [ -n "$since" ]; then
                grep "sshd" "/var/log/auth.log" | grep "Failed password" | awk -v last="$since" '$0 > last' | wc -l
            else
                grep "sshd" "/var/log/auth.log" | grep "Failed password" | wc -l
            fi
        elif [ -f "/var/log/secure" ]; then
            if [ -n "$since" ]; then
                grep "sshd" "/var/log/secure" | grep "Failed password" | awk -v last="$since" '$0 > last' | wc -l
            else
                grep "sshd" "/var/log/secure" | grep "Failed password" | wc -l
            fi
        elif command -v journalctl >/dev/null 2>&1; then
            local since_flag="--since=today"
            [ -n "$since" ] && since_flag="--since=$since"
            journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service $since_flag 2>/dev/null | grep -ci "failed.*password\|authentication.*failure" || echo 0
        else
            echo "无法获取"
        fi
    }

    # 获取上次成功登录时间
    LAST_SUCCESS=""
    if [ -f "/var/log/auth.log" ]; then
        LAST_SUCCESS=$(grep "sshd" "/var/log/auth.log" | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
    elif [ -f "/var/log/secure" ]; then
        LAST_SUCCESS=$(grep "sshd" "/var/log/secure" | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
    elif command -v journalctl >/dev/null 2>&1; then
        LAST_SUCCESS=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service 2>/dev/null | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
    fi

    FAILED_SINCE_LAST=$(get_failed_count "$LAST_SUCCESS")

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

    echo -e "

    \e[35m
            __  __    _    ___  ____  _______   ___   _
            |  \/  |  / \  / _ \|  _ \| ____\ \ / / | | |
            | |\/| | / _ \| | | | | | |  _|  \ V /| | | |
            | |  | |/ ___ \ |_| | |_| | |___  | | | |_| |
            |_|  |_/_/   \_\___/|____/|_____| |_|  \___/
    \e[0m



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

echo "请重连查看效果"
