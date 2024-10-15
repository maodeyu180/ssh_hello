#!/bin/bash
echo "正在生成ssh_hello 文件"
cat << EOF > /etc/profile.d/ssh_hello.sh
warning=$(if [ "$(df -m / | grep -v File | awk '{print $4}')" == "0" ];then echo " 警告，存储空间已满，请立即检查和处置！";fi)
IP=$(ifconfig eth0 | grep '\<inet\>'| grep -v '127.0.0.1' | awk '{print $2}' | awk 'NR==1')
mac_now=$(ifconfig eth0 |grep "ether"| awk '{print $2}')
if command -v sensors &> /dev/null; then
        temp=$(sensors | grep -i 'temp1' | awk '{print $2}')
else
        temp="无法检测 (请安装 lm-sensors)"
fi
# 当前连接的 IP 地址
CURRENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
# 上次连接的 IP 地址和时间
LAST_INFO=$(last -i | grep "pts/" | head -2 | tail -1)
if [ -n "$LAST_INFO" ]; then
    LAST_IP=$(echo $LAST_INFO | awk '{print $3}')
    LAST_TIME=$(echo $LAST_INFO | awk '{for(i=4;i<=NF-1;i++) printf $i" "; print $(NF)}')
else
    LAST_IP=None
    LAST_TIME=None
fi
CURRENT_SSH_CONNECTIONS=$(who | grep 'pts/' | wc -l)
clear
echo -e "


\e[35m
         __  __    _    ___  ____  _______   ___   _
        |  \/  |  / \  / _ \|  _ \| ____\ \ / / | | |
        | |\/| | / _ \| | | | | | |  _|  \ V /| | | |
        | |  | |/ ___ \ |_| | |_| | |___  | | | |_| |
        |_|  |_/_/   \_\___/|____/|_____| |_|  \___/
\e[0m



   CPU 信息 : $(cat /proc/cpuinfo | grep "processor" | sort | uniq | wc -l)核处理器 | $(uname -p)架构
   系统版本 : $(awk -F '[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release) | $(uname -r)-$(getconf LONG_BIT)
   可用存储 : $(df -m / | grep -v File | awk '{a=$4*100/$2;b=$4} {printf("%.1f%s %.1fM\n",a,"%",b)}') ${warning}
   可用内存 : $(free -m | grep Mem | awk '{a=$7*100/$2;b=$7} {printf("%.1f%s %.1fM\n",a,"%",b)}')
   启动时间 : $(awk '{a=int($1/86400);b=int(($1%86400)/3600);c=int(($1%3600)/60);d=int($1%60)} {printf("%d 天 %d 小时 %d 分钟 %d 秒\n",a,b,c,d)}' /proc/uptime)
   设备 IP  : $IP
   设备温度 : $temp
   MAC 地址 : $mac_now
   本次 IP  : $CURRENT_IP
   上次 IP  : $LAST_IP
   LAST TIME: $LAST_TIME
   SSH连接数：$CURRENT_SSH_CONNECTIONS
"


EOF
echo "授予ssh_hello 可执行权限"
chmod 744 /etc/profile.d/ssh_hello.sh

echo "请重连查看效果"