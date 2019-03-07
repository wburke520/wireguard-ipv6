#!/bin/bash

# 高速新VPN协议WireGuard服务端一键脚本
# GCP香港  和 Vutrl  搬瓦工 测试可用，已经添加自动判断网卡名
# OpenVZ  PVE 不能用

# Windows TunSafe版客户端
# https://tunsafe.com/download

# Debian9  安装 WireGuard 步骤
# 详细参考  https://www.mfzy.cf

# Debian 默认往往都没有 linux-headers 内核，而安装使用 WireGuard 必须要

# 更新软件包源
apt update

# 安装和 linux-image 内核版本相对于的 linux-headers 内核
apt install linux-headers-$(uname -r) -y

# Debian9 安装后内核列表
dpkg -l|grep linux-headers

# 安装WireGuard
# 添加 unstable 软件包源，以确保安装版本是最新的
echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
 
# 更新一下软件包源
apt update
 
# 开始安装 WireGuard ，和辅助库 resolvconf
apt install wireguard resolvconf -y

# 验证是否安装成功
modprobe wireguard && lsmod | grep wireguard

# 配置步骤 WireGuard服务端

# 首先进入配置文件目录
mkdir -p /etc/wireguard
cd /etc/wireguard

# 然后开始生成 密匙对(公匙+私匙)。
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey

# 获得服务器ip
serverip=$(curl -4 ip.sb)

# 生成服务端配置文件
echo "[Interface]
# 私匙，自动读取上面刚刚生成的密匙内容
PrivateKey = $(cat sprivatekey)
# VPN中本机的内网IP，一般默认即可，除非和你服务器或客户端设备本地网段冲突
Address = 10.0.0.1/24, fd10:db31:203:ab31::1/64 
# 运行 WireGuard 时要执行的 iptables 防火墙规则，用于打开NAT转发之类的。
# 如果你的服务器主网卡名称不是 eth0 ，那么请修改下面防火墙规则中最后的 eth0 为你的主网卡名称。
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# 如果你的服务器主网卡名称不是 eth0 ，那么请修改下面防火墙规则中最后的 eth0 为你的主网卡名称。
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
# 服务端监听端口，可以自行修改
ListenPort = 9999
# 服务端请求域名解析 DNS
DNS = 8.8.8.8, 2001:4860:4860::8888 
# 保持默认
MTU = 1420
[Peer]
# 公匙，自动读取上面刚刚生成的密匙内容
PublicKey = $(cat cpublickey)
# VPN内网IP范围，一般默认即可，除非和你服务器或客户端设备本地网段冲突
AllowedIPs = 10.0.0.2/32, fd10:db31:203:ab31::2/64" > wg0.conf

# 生成客户端配置文件
echo "[Interface]
# 私匙，自动读取上面刚刚生成的密匙内容
PrivateKey = $(cat cprivatekey)
# VPN内网IP范围
Address = 10.0.0.2/24,fd10:db31:203:ab31::2/64
# 解析域名用的DNS
DNS = 8.8.8.8, 2001:4860:4860::8888
# 保持默认
MTU = 1300
# Wireguard客户端配置文件加入PreUp,Postdown命令调用批处理文件
PreUp = start   .\route\routes-up.bat
PostDown = start  .\route\routes-down.bat
#### 正常使用Tunsafe点击connect就会调用routes-up.bat将国内IP写进系统路由表，断开disconnect则会调用routes-down.bat删除路由表。
#### 连接成功后可上 http://ip111.cn/ 测试自己的IP。
[Peer]
# 公匙，自动读取上面刚刚生成的密匙内容
PublicKey = $(cat spublickey)
# 服务器地址和端口，下面的 X.X.X.X 记得更换为你的服务器公网IP，端口根据服务端配置时的监听端口填写
Endpoint = $serverip:9009
# 转发流量的IP范围，下面这个代表所有流量都走VPN
AllowedIPs = 0.0.0.0/0, ::0/0
# 保持连接，如果客户端或服务端是 NAT 网络(比如国内大多数家庭宽带没有公网IP，都是NAT)，
# 那么就需要添加这个参数定时链接服务端(单位：秒)，如果你的服务器和你本地都不是 NAT 网络，
# 那么建议不使用该参数（设置为0，或客户端配置文件中删除这行）
PersistentKeepalive = 25"|sed '/^#/d;/^\s*$/d' > client.conf

# 赋予配置文件夹权限
chmod 777 -R /etc/wireguard
 
sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

# 开启 BBR
sysctl_config
lsmod | grep bbr
 
# 打开防火墙转发功能
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.accept_ra=2" >> /etc/sysctl.conf
sysctl -p

# 启动WireGuard
wg-quick up wg0

# 设置开机启动
systemctl enable wg-quick@wg0

# 查询WireGuard状态
wg

# 定义修改端口号，适合已经安装WireGuard而不想改端口
port=9999
mtu=1420
ip_list=(2 5 8 178 186 118 158 198 168 9)

#定义文字颜色
Green="\033[32m"  && Red="\033[31m" && GreenBG="\033[42;37m" && RedBG="\033[41;37m" && Font="\033[0m"

#定义提示信息
Info="${Green}[信息]${Font}"  &&  OK="${Green}[OK]${Font}"  &&  Error="${Red}[错误]${Font}"

# 检查是否安装 WireGuard
if [ ! -f '/usr/bin/wg' ]; then
    clear
    echo -e "${RedBG}   一键安装 WireGuard 脚本 For Debian_9 Ubuntu Centos_7   ${Font}"
    echo -e "${GreenBG}     开源项目：https://github.com/hongwenjun/vps_setup    ${Font}"
    help_info
    echo -e "${Red}::  检测到你的vps没有安装wireguard，请选择复制一键脚本安装   ${Font}"
    exit 1
fi

host=$(hostname -s)
# 获得服务器ip，自动获取
if [ ! -f '/usr/bin/curl' ]; then
    apt update && apt install -y curl
fi
serverip=$(curl -4 ip.sb)

# 安装二维码插件
if [ ! -f '/usr/bin/qrencode' ]; then
    apt -y install qrencode
fi


# wg配置文件目录 /etc/wireguard
mkdir -p /etc/wireguard
chmod 777 -R /etc/wireguard
cd /etc/wireguard

# 然后开始生成 密匙对(公匙+私匙)。
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey

# 生成服务端配置文件
cat <<EOF >wg0.conf
[Interface]
PrivateKey = $(cat sprivatekey)
Address = 10.0.0.1/24 
Address = fd10:db31:203:ab31::1/64 
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = $port
DNS = 8.8.8.8, 2001:4860:4860::8888 
MTU = $mtu
[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = 10.0.0.188/32, fd10:db31:203:ab31::2
EOF

# 生成简洁的客户端配置
cat <<EOF >client.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = 10.0.0.188/24
Address = fd10:db31:203:ab31::2/64
DNS = 8.8.8.8, 2001:4860:4860::8888
#  MTU = $mtu
#  PreUp =  start   .\route\routes-up.bat
#  PostDown = start  .\route\routes-down.bat
[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

# 添加 2-9 号多用户配置
for i in {2..9}
do
    ip=10.0.0.${ip_list[$i]}
    ip6=fd10:db31:203:ab31::${ip_list[$i]}
    wg genkey | tee cprivatekey | wg pubkey > cpublickey

    cat <<EOF >>wg0.conf
[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = $ip/32, $ip6
EOF

    cat <<EOF >wg_${host}_$i.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = $ip/24
Address = $ip6/64
DNS = 8.8.8.8, 2001:4860:4860::8888
[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF
    cat /etc/wireguard/wg_${host}_$i.conf| qrencode -o wg_${host}_$i.png
done

#  vps网卡如果不是eth0，修改成实际网卡
ni=$(ls /sys/class/net | awk {print} | grep -e eth. -e ens. -e venet.)
if [ $ni != "eth0" ]; then
    sed -i "s/eth0/${ni}/g"  /etc/wireguard/wg0.conf
fi

# 重启wg服务器
wg-quick down wg0
wg-quick up wg0
