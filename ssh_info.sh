#!/bin/bash
echo "正在生成ssh_hello 文件"
rm -rf /etc/profile.d/ssh_hello.sh
cat << 'EOF' > /etc/profile.d/ssh_hello.sh
if [ -n "$SSH_CONNECTION" ]; then
  warning=$(if [ "$(df -m / | grep -v File | awk '{print $4}')" == "0" ];then echo " 警告，存储空间已满，请立即检查和处置！";fi)
  if command -v ifconfig &> /dev/null; then
    INTERFACE=$(ifconfig -a | grep -m 1 'flags=' | awk -F: '{print $1}')
    IP=$(ifconfig $INTERFACE | grep '\<inet\>'| grep -v '127.0.0.1' | awk '{print $2}' | awk 'NR==1')
    IPV6=$(ifconfig $INTERFACE | grep '\<inet6\>' | awk '{print $2}' | awk 'NR==1')
  else
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n 1)
    IP=$(ip addr show $INTERFACE | grep '\<inet\>' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | awk 'NR==1')
    IPV6=$(ip addr show $INTERFACE | grep '\<inet6\>' | awk '{print $2}' | cut -d/ -f1 | awk 'NR==1')
  fi
  mac_now=$(ifconfig eth0 |grep "ether"| awk '{print $2}')
  if command -v sensors &> /dev/null; then
      temps=$(sensors | grep -i 'core\|package' | awk '{print $3}' | tr -d '+°C')
      if [ -n "$temps" ]; then
          sum=0
          count=0
          for temp_val in $temps; do
              sum=$(echo "$sum + $temp_val" | bc)
              count=$((count + 1))
          done
          avg_temp=$(echo "scale=1; $sum / $count" | bc)
          temp="${avg_temp}°C"
      else
          temp="无法检测 (传感器输出无匹配项)"
      fi
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


# 获取上次成功登录时间
if [ -f "/var/log/auth.log" ]; then
    # Debian/Ubuntu 传统日志
    LAST_SUCCESS=$(grep "sshd" "/var/log/auth.log" | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
elif [ -f "/var/log/secure" ]; then
    # RHEL/CentOS 传统日志
    LAST_SUCCESS=$(grep "sshd" "/var/log/secure" | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
elif command -v journalctl >/dev/null 2>&1; then
    # systemd journal
    LAST_SUCCESS=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service | grep "Accepted" | grep "$USER" | tail -2 | head -1 | awk '{print $1" "$2" "$3}')
fi

# 获取失败尝试次数
if [ -n "$LAST_SUCCESS" ]; then
    if [ -f "/var/log/auth.log" ]; then
        # Debian/Ubuntu 传统日志
        FAILED_SINCE_LAST=$(grep "sshd" "/var/log/auth.log" | grep "Failed password" | awk -v last="$LAST_SUCCESS" '$0 > last' | wc -l)
    elif [ -f "/var/log/secure" ]; then
        # RHEL/CentOS 传统日志
        FAILED_SINCE_LAST=$(grep "sshd" "/var/log/secure" | grep "Failed password" | awk -v last="$LAST_SUCCESS" '$0 > last' | wc -l)
    elif command -v journalctl >/dev/null 2>&1; then
        # systemd journal - 改进的失败统计
        FAILED_SINCE_LAST=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service --since="$LAST_SUCCESS" | grep -i "failed\|failure" | grep -i "password\|authentication" | wc -l)
    else
        FAILED_SINCE_LAST="无法获取"
    fi
else
    if [ -f "/var/log/auth.log" ]; then
        FAILED_SINCE_LAST=$(grep "sshd" "/var/log/auth.log" | grep "Failed password" | wc -l)
    elif [ -f "/var/log/secure" ]; then
        FAILED_SINCE_LAST=$(grep "sshd" "/var/log/secure" | grep "Failed password" | wc -l)
    elif command -v journalctl >/dev/null 2>&1; then
        # systemd journal - 改进的失败统计（今日）
        FAILED_SINCE_LAST=$(journalctl _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service --since=today | grep -i "failed\|failure" | grep -i "password\|authentication" | wc -l)
    else
        FAILED_SINCE_LAST="无法获取"
    fi
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
     设备 IP  : $IP / $IPV6
     设备温度 : $temp
     MAC 地址 : $mac_now
     本次 IP  : $CURRENT_IP
     上次 IP  : $LAST_IP
     LAST TIME: $LAST_TIME
     SSH连接数：$CURRENT_SSH_CONNECTIONS
     失败次数 ：$FAILED_SINCE_LAST
  "
fi
EOF
echo "授予ssh_hello 可执行权限"
chmod 744 /etc/profile.d/ssh_hello.sh

echo "请重连查看效果"
