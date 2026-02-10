#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "Данный скрипт не поддерживает текущую операционную систему. Пожалуйста, выберите Ubuntu, Debian или CentOS." && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "Скрипт не поддерживает текущую версию. $op Пожалуйста, выберите Ubuntu, Debian или CentOS в качестве вашей операционной системы.。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "В настоящее время скрипт не поддерживает...$(uname -m)架构" && exit;;
esac
#bit=$(uname -m)
#if [[ $bit = "aarch64" ]]; then
#cpu="arm64"
#elif [[ $bit = "x86_64" ]]; then
#amdv=$(cat /proc/cpuinfo | grep flags | head -n 1 | cut -d: -f2)
#[[ $amdv == *avx2* && $amdv == *f16c* ]] && cpu="amd64v3" || cpu="amd64"
#else
#red "В настоящее время скрипт не поддерживает... $bit 架构" && exit
#fi
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

if [ ! -f sbyg_update ]; then
green "Впервые для скрипта Sing-box-yg были определены необходимые зависимости..."
if [[ x"${release}" == x"alpine" ]]; then
apk update
apk add jq openssl iproute2 iputils coreutils expect git socat iptables grep util-linux dcron tar tzdata 
apk add virt-what
else
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v apt-get)" ]; then
apt update -y
apt install jq cron socat iptables-persistent coreutils util-linux -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat coreutils util-linux -y
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
fi
if [[ -z $vi ]]; then
apt install iputils-ping iproute2 systemctl -y
fi

packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
fi
touch sbyg_update
fi

if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ 'В состоянии ошибки' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "Функция TUN не была включена; сейчас мы пытаемся добавить поддержку TUN." && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ 'В состоянии ошибки' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "Не удалось добавить поддержку TUN. Рекомендуем связаться с вашим VPS-провайдером или включить её в настройках административной панели." && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "Функция защиты TUN активирована."
fi
fi
fi

v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
}

warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6(){
v4orv6(){
if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "Обнаружен VPS, работающий исключительно по протоколу IPv6; добавлен NAT64."
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
ipv=prefer_ipv6
else
ipv=prefer_ipv4
fi
if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
endip=2606:4700:d0::a29f:c001
else
endip=162.159.192.1
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

argopid(){
ym=$(cat /etc/s-box/sbargoympid.log 2>/dev/null)
ls=$(cat /etc/s-box/sbargopid.log 2>/dev/null)
}

close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "Открытие портов и отключение брандмауэра завершены."
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "Открыть порты и отключить брандмауэр? 1. Да, выполнить (Введите для значения по умолчанию) 2. Нет, пропустить! Обработайте по мере необходимости. Пожалуйста, выберите [1-2]：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "Ошибка ввода, пожалуйста, выберите еще раз." && openyn
fi
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "Какая версия ядра используется?：1.10Официальная версия ядра этой серии поддерживает маршрутизацию по географическим местоположениям.，1.10Последующие версии ядра, выходящие за рамки этой серии, не поддерживают маршрутизацию по географическим местоположениям."
yellow "1：Используйте последнюю официальную версию ядра после 1.10 (Введите значение по умолчанию)"
yellow "2：Используется версия ядра 1.10.7
readp "Пожалуйста, выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
#sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
sbcore="1.12.19"
else
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\.10[0-9\.]*",'  | sed -n 1p | tr -d '",')
fi
sbname="sing-box-$sbcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "成功Пожалуйста используйтеить Sing-box версия ядра：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
else
red "Загрузка ядра Sing-box не завершена.，Пожалуйста используйтеить失败，Пожалуйста, запустите его еще разПожалуйста используйте один раз" && exit
fi
else
red "Загрузка ядра Sing-box не удалась. Пожалуйста, запустите еще раз и проверьте, есть ли у сети вашего VPS доступ к GitHub." && exit
fi
}

inscertificate(){
ymzs(){
ym_vl_re=apple.com
echo
blue "Vless-realityИмя домена SNI по умолчанию — apple.com"
blue "Vmess-ws включит TLS; Hysteria-2 и Tuic-v5 будут его использовать. $(cat /root/ygkkkca/ca.log 2>/dev/null) Сертификат и включите проверку сертификата SNI."
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
}

zqzs(){
ym_vl_re=apple.com
echo
blue "Vless-realityИмя домена SNI по умолчанию — apple.com"
blue "Vmess-ws отключит TLS, Hysteria-2 и Tuic-v5 будут использовать самоподписанные сертификаты Bing и отключат проверку сертификатов SNI."
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
}

red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "二、生成并设置相关证书"
echo
blue "自动生成bing自签证书中……" && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "生成bing自签证书成功"
else
red "生成bing自签证书失败" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名证书：$(cat /root/ygkkkca/ca.log) "
green "是否使用 $(cat /root/ygkkkca/ca.log) 域名证书？"
yellow "1：否！使用自签的证书 (回车默认)"
yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名证书"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "Если у вас уже есть доменное имя, которое было разрешено, хотите ли вы подать заявку на новоеAcmeСертификат домена？"
yellow "1: Нет! Продолжайте использовать самоподписанный сертификат. (Введите значения по умолчанию для клавиш.)"
yellow "2: Да! Используйте скрипт Acme-yg для подачи заявки на получение сертификата Acme. (Поддерживает как стандартный режим порта 80, так и режим DNS API.)"
readp "Пожалуйста, выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Заявка на получение сертификата Acme не удалась, продолжайте использовать самоподписанный сертификат." 
zqzs
else
ymzs
fi
fi
fi
}

chooseport(){
if [[ -z $port ]]; then
port=$(shuf -i 10000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nпорт被占用，请重新输入порт" && readp "Обычайпорт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nпорт被占用，请重新输入порт" && readp "Обычайпорт:" port
done
fi
blue "确认的порт：$port" && sleep 2
}

vlport(){
readp "\nНастройте порт Vless-reality.[1-65535] (Нажмите Enter, чтобы пропустить10000-65535Случайные порты между)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\nНастройте порт Vmess-ws.[1-65535] (Нажмите Enter, чтобы пропустить10000-65535Случайные порты между)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\nНастройте основной порт Hysteria2.[1-65535] (Нажмите Enter, чтобы пропустить10000-65535Случайные порты между)：" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\nНастройка главного порта Tuic5[1-65535] (Нажмите Enter, чтобы пропустить10000-65535Случайные порты между)：" port
chooseport
port_tu=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "III. Настройте каждый порт протокола."
yellow "1：Автоматическая генерация случайных портов для каждого протокола. (10000-65535В пределах досягаемости)，Введите значения по умолчанию для клавиш."
yellow "2: Настройте каждый порт протокола."
readp "Пожалуйста, введите【1-2】：" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..4}; do
while true; do
port=$(shuf -i 10000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
do
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
done
echo
blue "В зависимости от того, включена ли технология TLS в протоколе Vmess-ws, случайным образом назначается стандартный порт, поддерживающий предпочтительные IP-адреса CDN:$port_vm_ws"
else
vlport && vmport && hy2port && tu5port
fi
echo
blue "Подтверждены следующие протокольные порты:"
blue "Vless-realityпорт：$port_vl_re"
blue "Vmess-wsпорт：$port_vm_ws"
blue "Hysteria-2порт：$port_hy2"
blue "Tuic-v5порт：$port_tu"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "IV. Автоматическая генерация единого UUID для различных протоколов. (пароль)"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "Подтвержденныйuuid (пароль)：${uuid}"
blue "ПодтвержденныйПуть Vmess：${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":2408,
"local_address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":$res
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"rules":[
{
"protocol": [
"quic",
"stun"
],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",

      
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",

 
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",

 
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",

     
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
],
"endpoints":[
{
"type":"wireguard",
"tag":"warp-out",
"address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peers": [
{
"address": "$endip",
"port":2408,
"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"allowed_ips": [
"0.0.0.0/0",
"::/0"
],
"reserved":$res
}
]
}
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag":"vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
}
],
"route":{
"rules":[
{
 "action": "sniff"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv4"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv6"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"socks-out"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"warp-out"
},
{
"outbound":"vps-outbound-v4",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
if [[ x"${release}" == x"alpine" ]]; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
}

ipuuid(){
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6
if [[ -n $v4 && -n $v6 ]]; then
green "双栈VPS需要选择IP配置输出，一般情况下nat vps建议选择IPV6"
yellow "1：使用IPV4配置输出 (Введите значения по умолчанию для клавиш.) "
yellow "2：使用IPV6配置输出"
readp "Пожалуйста, выберите【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ]; then
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$v4"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v4"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$v6]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v6"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
else
yellow "VPS并不是双栈VPS，不поддерживатьIP配置输出的切换"
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$serip]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$serip"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
fi
else
red "Sing-box服务еще нет运行" && exit
fi
}

wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

result_vl_vm_hy_tu(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
ym=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
echo $ym > /root/ygkkkca/ca.log
fi
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
sbdnsip=$(cat /etc/s-box/sbdnsip.log)
server_ip=$(cat /etc/s-box/server_ip.log)
server_ipcl=$(cat /etc/s-box/server_ipcl.log)
uuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vl_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
public_key=$(cat /etc/s-box/public.key)
short_id=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.short_id[0]')
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
ws_path=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
if [[ -f /etc/s-box/cfvmadd_local.txt ]]; then
vmadd_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
vmadd_are_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
else
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
fi
if [[ -f /etc/s-box/cfvmadd_argo.txt ]]; then
vmadd_argo=$(cat /etc/s-box/cfvmadd_argo.txt 2>/dev/null)
else
vmadd_argo=www.visa.com.sg
fi
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
if [[ -n $hy2_ports ]]; then
hy2ports=$(echo $hy2_ports | sed 's/:/-/g')
hyps=$hy2_port,$hy2ports
else
hyps=
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
fi
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
fi
}

resvless(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
echo "$vl_link" > /etc/s-box/vl_reality.txt
red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
echo
echo "Поделиться ссылкой【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "二维码【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下(可选择3-8-3，ОбычайCDN优选地址)：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argols.txt)"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，ОбычайCDN优选地址)：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argogd.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，Настроить为CDN优选节点)：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，Настроить为CDN优选节点)：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_tls.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_tls.txt)"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

reshy2(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
#hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#hy2-$hostname"
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
echo "$hy2_link" > /etc/s-box/hy2.txt
red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins&allowInsecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
echo
echo "Поделиться ссылкой【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

sb_client(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
           "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname",
"vmess-tls-argo临时-$hostname",
"vmess-argo临时-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo固定-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo临时-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo临时-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname",
"vmess-tls-argo临时-$hostname",
"vmess-argo临时-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: chrome                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: vmess-tls-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd


- name: vmess-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-tls-argo临时-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo临时-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF


elif [[ ! -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
           "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo临时-$hostname",
"vmess-argo临时-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo临时-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo临时-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo临时-$hostname",
"vmess-argo临时-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: chrome                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins









- name: vmess-tls-argo临时-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo临时-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo临时-$hostname
    - vmess-argo临时-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF

elif [[ -n $(ps -e | grep -w $ym 2>/dev/null) && ! -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
     "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo固定-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: chrome                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins







- name: vmess-tls-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF

else
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
     "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                    
  client-fingerprint: chrome                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     





- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF
fi

cat > /etc/s-box/v2rayn_hy2.yaml <<EOF
server: $sb_hy2_ip:$hy2_port
auth: $uuid
tls:
  sni: $hy2_name
  insecure: $hy2_ins
fastOpen: true
socks5:
  listen: 127.0.0.1:50000
lazy: true
transport:
  udp:
    hopInterval: 30s
EOF

cat > /etc/s-box/v2rayn_tu5.json <<EOF
{
    "relay": {
        "server": "$sb_tu5_ip:$tu5_port",
        "uuid": "$uuid",
        "password": "$uuid",
        "congestion_control": "bbr",
        "alpn": ["h3", "spdy/3.1"]
    },
    "local": {
        "server": "127.0.0.1:55555"
    },
    "log_level": "info"
}
EOF
if [[ -n $hy2_ports ]]; then
hy2_ports=",$hy2_ports"
hy2_ports=$(echo $hy2_ports | sed 's/:/-/g')
a=$hy2_ports
sed -i "/server:/ s/$/$a/" /etc/s-box/v2rayn_hy2.yaml
fi
sed -i 's/server: \(.*\)/server: "\1"/' /etc/s-box/v2rayn_hy2.yaml
}

cfargo_ym(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
echo
yellow "1：Временный туннель Арго"
yellow "2：Стационарный тоннель Арго"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
cfargo
elif [ "$menu" = "2" ]; then
cfargoym
else
changeserv
fi
else
yellow "Туннелирование Argo недоступно, поскольку в vmess включен протокол TLS" && sleep 2
fi
}

cloudflaredargo(){
if [ ! -e /etc/s-box/cloudflared ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
#curl -L -o /etc/s-box/cloudflared -# --retry 2 https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/$cpu
chmod +x /etc/s-box/cloudflared
fi
}

cfargoym(){
echo
if [[ -f /etc/s-box/sbargotoken.log && -f /etc/s-box/sbargoym.log ]]; then
green "Текущий домен фиксированного туннеля Argo：$(cat /etc/s-box/sbargoym.log 2>/dev/null)"
green "Токен для фиксированного туннеля Арго：$(cat /etc/s-box/sbargotoken.log 2>/dev/null)"
fi
echo
green "Пожалуйста, посетите официальный сайт Cloudflare --- Zero Trust --- Networks --- Tunnelsнастройка завершена"
yellow "1：Сброс/Установка фиксированного туннельного домена Argo"
yellow "2：Остановка Арго, стационарный туннель"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
readp "Введите токен для стационарного туннеля Argo: " argotoken
readp "Введите доменное имя фиксированного туннеля Argo: " argoym
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
fi
echo
if [[ -n "${argotoken}" && -n "${argoym}" ]]; then
nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken} >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbargoympid.log
sleep 20
fi
echo ${argoym} > /etc/s-box/sbargoym.log
echo ${argotoken} > /etc/s-box/sbargotoken.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat /etc/s-box/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargoympid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
argo=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
blue "Установка стационарного туннеля Argo завершена，фиксированное доменное имя：$argo"
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
crontab -l > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argogd.txt
green "Строительство стационарного тоннеля Argo прекращено."
else
cfargo_ym
fi
}

cfargo(){
echo
yellow "1：Сбросить временный домен туннеля Argo"
yellow "2：Остановите временный туннель "Арго""
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
i=0
while [ $i -le 4 ]; do let i++
yellow "第$iЭто обновление подтверждает подлинность Cloudflare Срок действия временного туннельного домена Argo истекает, пожалуйста, подождите..."
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
fi
nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
echo "$!" > /etc/s-box/sbargopid.log
sleep 20
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400|503/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
blue "Временное туннелирование Argo успешно запущено, проверка домена действительна：$argo" && sleep 2
break
fi
if [ $i -eq 5 ]; then
echo
yellow "Временная проверка домена Argo временно недоступна. Она может быть автоматически восстановлена ​​позже, или вы можете запросить сброс" && sleep 3
fi
done
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargopid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argols.txt
green "Временный туннель Арго закрыт."
else
cfargo_ym
fi
}

instsllsingbox(){
if [[ -f '/etc/systemd/system/sing-box.service' ]]; then
red "Пожалуйста ЗАЦЕНИ, Услуга Sing-box завершена и не может быть использована снова" && exit
fi
mkdir -p /etc/s-box
v6
openyn
inssb
inscertificate
insport
sleep 2
echo
blue "Vless-reality相关key与id将自动生成……"
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "5. Автоматическое создание исходящих учетных записей warp-wireguard" && sleep 2
warpwg
inssbjsonser
sbservice
sbactive
#curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "Обновить контент" '{print $1}' | head -n 1 > /etc/s-box/v
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "Обновить контент" '{print $1}' | head -n 1 > /etc/s-box/v
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Sing-box-yg脚本Пожалуйста используйтеить成功，Ярлык скрипта：sb" && cronsb
echo
wgcfgo
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "Hysteria2/Tuic5ОбычайV2rayN配置、Clash-Meta/Sing-boxНастройка клиента и частная ссылка для подписки，Пожалуйста, выберите9查看"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellowПереключиться на Сертификат домена：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellowеще нетЯ подал заявку на получение сертификата домена, но не могу переключиться$plain"
vl_na="Доменное имя используется：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')。$yellowИзмените доменное имя в соответствии с требованиями компании Reality，不поддерживать证书域名$plain"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
[[ "$tls" = "false" ]] && vm_na="Текущий已关闭TLS。$ymzs ${yellow}Протокол TLS будет включен; туннель Argo не будет включен${plain}" || vm_na="В настоящее время используется домена：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为关闭TLS，Argo隧道将可用$plain"
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="Использование самоподписанного сертификата Bing。$ymzs" || hy2_na="В настоящее время используется домена：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="Использование самоподписанного сертификата Bing。$ymzs" || tu5_na="В настоящее время используется домена：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
echo
green "Пожалуйста, выберите протокол для переключения режимов сертификата"
green "1：vless-realityпротокол，$vl_na"
if [[ -f /root/ygkkkca/ca.log ]]; then
green "2：vmess-wsпротокол，$vm_na"
green "3：Hysteria2протокол，$hy2_na"
green "4：Tuic5протокол，$tu5_na"
else
red "толькоподдерживать选项1 (vless-reality)。因еще нет申请Сертификат домена，vmess-ws、Hysteria-2、Tuic-v5В данный момент опция переключения сертификата не отображается"
fi
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "Пожалуйста, введитеvless-reality域名 (Нажмите Enterapple.com)：" menu
ym_vl_re=${menu:-apple.com}
a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.handshake.server')
c=$(cat /etc/s-box/vl_reality.txt | cut -d'=' -f5 | cut -d'&' -f1)
echo $sbfiles | xargs -n1 sed -i "23s/$a/$ym_vl_re/"
echo $sbfiles | xargs -n1 sed -i "27s/$b/$ym_vl_re/"
restartsb
blue "После завершения настройки вернитесь в главное меню и перейдите к пункту 9, чтобы обновить конфигурацию узла."
elif [ "$menu" = "2" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
[ "$a" = "true" ] && a_a=false || a_a=true
b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
[ "$b" = "www.bing.com" ] && b_b=$(cat /root/ygkkkca/ca.log) || b_b=$(cat /root/ygkkkca/ca.log)
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "55s#$a#$a_a#"
echo $sbfiles | xargs -n1 sed -i "56s#$b#$b_b#"
echo $sbfiles | xargs -n1 sed -i "57s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "58s#$d#$d_d#"
restartsb
blue "После завершения настройки вернитесь в главное меню и перейдите к пункту 9, чтобы обновить конфигурацию узла."
echo
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
blue "ТекущийVmess-ws(tls)的порт：$vm_port"
[[ "$tls" = "false" ]] && blue "切记：可进入主菜单选项4-2，将Vmess-wsпорт更改为任意7个80系порт(80、8080、8880、2052、2082、2086、2095)，可实现CDN优选IP" || blue "切记：可进入主菜单选项4-2，将Vmess-ws-tlsпорт更改为任意6个443系的порт(443、8443、2053、2083、2087、2096)，可实现CDN优选IP"
echo
else
red "Форма заявления не подлежит изменению. Для подачи заявки на получение сертификата Acme выберите пункт 12 в главном меню" && sleep 2 && sb
fi
elif [ "$menu" = "3" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "79s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "80s#$d#$d_d#"
restartsb
blue "После завершения настройки вернитесь в главное меню и перейдите к пункту 9, чтобы обновить конфигурацию узла."
else
red "Форма заявления не подлежит изменению. Для подачи заявки на получение сертификата Acme выберите пункт 12 в главном меню" && sleep 2 && sb
fi
elif [ "$menu" = "4" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.certificate_path')
d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
echo $sbfiles | xargs -n1 sed -i "102s#$c#$c_c#"
echo $sbfiles | xargs -n1 sed -i "103s#$d#$d_d#"
restartsb
blue "После завершения настройки вернитесь в главное меню и перейдите к пункту 9, чтобы обновить конфигурацию узла."
else
red "Форма заявления не подлежит изменению. Для подачи заявки на получение сертификата Acme выберите пункт 12 в главном меню" && sleep 2 && sb
fi
else
sb
fi
}

allports(){
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="еще нет添加"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="еще нет添加"
}

changeport(){
sbactive
allports
fports(){
readp "\nПожалуйста, введите диапазон портов для переадресации. (1000-65535В пределах досягаемости，Формат: малое число:большое число)：" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Диапазон портов для переадресации подтвержден.：$rangeport"
else
red "Диапазон входных портов больше недействителен.В пределах досягаемости" && fports
fi
else
red "Неправильный формат ввода。Формат: малое число:большое число" && fports
fi
echo
}
fport(){
readp "\nПожалуйста, введите一个转发的порт (1000-65535В пределах досягаемости)：" onlyport
if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "Подтвержденный转发的порт：$onlyport"
else
blue "Входной порт больше не действителен" && fport
fi
echo
}

hy2deports(){
allports
hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$hy2_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}
tu5deports(){
allports
tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$tu5_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}

allports
green "Vless-reality и Vmess-ws могут изменять уникальный PID, а vmess-ws отмечает сброс Argopid"
green "Поддержка Hysteria2 и Tuic5 Изменить основной порт, а также поддержку Добавить или удалить несколько переадресованных портов"
green "Hysteria2поддерживатьпорт跳跃，且与Tuic5都поддерживать多порт复用"
echo
green "1：Vless-realityпротокол ${yellow}порт:$vl_port${plain}"
green "2：Vmess-wsпротокол ${yellow}порт:$vm_port${plain}"
green "3：Hysteria2протокол ${yellow}порт:$hy2_port  转发多порт: $hy2zfport${plain}"
green "4：Tuic5протокол ${yellow}порт:$tu5_port  转发多порт: $tu5zfport${plain}"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите要变更порт的протокол【0-4】：" menu
if [ "$menu" = "1" ]; then
vlport
echo $sbfiles | xargs -n1 sed -i "14s/$vl_port/$port_vl_re/"
restartsb
blue "Vless-realityпортИзменения внесены. Теперь вы можете выбрать вариант 9 для вывода информации о конфигурации"
echo
elif [ "$menu" = "2" ]; then
vmport
echo $sbfiles | xargs -n1 sed -i "41s/$vm_port/$port_vm_ws/"
restartsb
blue "Vmess-wsпортИзменения внесены. Теперь вы можете выбрать вариант 9 для вывода информации о конфигурации"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
blue "Важно: Если используется Argo, необходимо перезагрузить временные туннели и изменить интерфейс CF На параметр для фиксированных туннелей$port_vm_ws"
else
blue "Туннель «Арго» больше не работает"
fi
echo
elif [ "$menu" = "3" ]; then
green "1：Замените основной порт Hysteria2 (Оригинальный многократный автоматический сброс и удаление)"
green "2：添加Hysteria2多порт"
green "3：重置删除Hysteria2多порт"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $hy2_ports ]; then
hy2deports
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb
result_vl_vm_hy_tu && reshy2 && sb_client
else
hy2port
echo $sbfiles | xargs -n1 sed -i "67s/$hy2_port/$port_hy2/"
restartsb
result_vl_vm_hy_tu && reshy2 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1：添加Hysteria2范围порт"
green "2：添加Hysteria2单порт"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $hy2_ports ]; then
hy2deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Hysteria2еще нетНастроить多порт" && changeport
fi
else
changeport
fi

elif [ "$menu" = "4" ]; then
green "1：Замените основную цепь Tuic5 (Оригинальный многократный автоматический сброс и удаление)"
green "2：Добавить многокомпонентную версию Tuic5"
green "3：Сбросьте и удалите Tuic5 несколько раз"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $tu5_ports ]; then
tu5deports
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb
result_vl_vm_hy_tu && restu5 && sb_client
else
tu5port
echo $sbfiles | xargs -n1 sed -i "89s/$tu5_port/$port_tu/"
restartsb
result_vl_vm_hy_tu && restu5 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1：Добавить диапазон Tuic5"
green "2：Добавить однопортовый модуль Tuic5"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $tu5_ports ]; then
tu5deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Tuic5еще нетНастроить多порт" && changeport
fi
else
changeport
fi
else
sb
fi
}

changeuuid(){
echo
olduuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
oldvmpath=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
green "Полный UUID протокола (пароль)：$olduuid"
green "Путь Vmess：$oldvmpath"
echo
yellow "1：ОбычайПолный UUID протокола (пароль)"
yellow "2：ОбычайПуть Vmess"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-2】：" menu
if [ "$menu" = "1" ]; then
readp "Введите свой UUID (он должен быть в формате UUID). Если вы не понимаете, нажмите Enter(Сбросить и сгенерировать случайный UUID)：" menu
if [ -z "$menu" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
else
uuid=$menu
fi
echo $sbfiles | xargs -n1 sed -i "s/$olduuid/$uuid/g"
restartsb
blue "Подтвержденныйuuid (пароль)：${uuid}" 
blue "ПодтвержденныйПуть Vmess：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
elif [ "$menu" = "2" ]; then
readp "输入Путь Vmess，Нажатие клавиши Enter означает отсутствие изменений：" menu
if [ -z "$menu" ]; then
echo
else
vmpath=$menu
echo $sbfiles | xargs -n1 sed -i "50s#$oldvmpath#$vmpath#g"
restartsb
fi
blue "ПодтвержденныйПуть Vmess：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')"
sbshare
else
changeserv
fi
}

changeip(){
v4v6
chip(){
rpip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[0].domain_strategy')
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sed -i "111s/$rpip/$rrpip/g" /etc/s-box/sb10.json
sed -i "134s/$rpip/$rrpip/g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
}
readp "1. IPV4приоритет\n2. IPV6приоритет\n3. толькоIPV4\n4. толькоIPV6\nПожалуйста, выберите：" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="IPV4приоритет($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="IPV6приоритет($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="толькоIPV4($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="толькоIPV6($v6)"
else 
red "Выбранный вами IPv4/IPv6-адрес не существует, или адрес был введен неправильно." && changeip
fi
blue "Текущий приоритет IP-адреса изменен：${v4_6}" && sb
}

tgsbshow(){
echo
yellow "1：Сбросить/установить токен и идентификатор пользователя Telegram-бота"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/s-box/sbtg.sh
readp "Введите токен бота Telegram: " token
telegram_token=$token
readp "Введите идентификатор пользователя Telegram-бота.: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8

total_lines=$(wc -l < /etc/s-box/clash_meta_client.yaml)
half=$((total_lines / 2))
head -n $half /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client2.txt

total_lines=$(wc -l < /etc/s-box/sing_box_client.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client3.txt
tail -n +$((3 * quarter + 1)) /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client4.txt

m1=$(cat /etc/s-box/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/s-box/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/s-box/vm_ws_argols.txt 2>/dev/null)
m3_5=$(cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null)
m4=$(cat /etc/s-box/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/s-box/hy2.txt 2>/dev/null)
m6=$(cat /etc/s-box/tuic5.txt 2>/dev/null)
m7=$(cat /etc/s-box/sing_box_client1.txt 2>/dev/null)
m7_5=$(cat /etc/s-box/sing_box_client2.txt 2>/dev/null)
m7_5_5=$(cat /etc/s-box/sing_box_client3.txt 2>/dev/null)
m7_5_5_5=$(cat /etc/s-box/sing_box_client4.txt 2>/dev/null)
m8=$(cat /etc/s-box/clash_meta_client1.txt 2>/dev/null)
m8_5=$(cat /etc/s-box/clash_meta_client2.txt 2>/dev/null)
m9=$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)
m10=$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)
m11=$(cat /etc/s-box/jh_sub.txt 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m3_5=$(echo "$m3_5")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m6=$(echo "$m6")
message_text_m7=$(echo "$m7")
message_text_m7_5=$(echo "$m7_5")
message_text_m7_5_5=$(echo "$m7_5_5")
message_text_m7_5_5_5=$(echo "$m7_5_5_5")
message_text_m8=$(echo "$m8")
message_text_m8_5=$(echo "$m8_5")
message_text_m9=$(echo "$m9")
message_text_m10=$(echo "$m10")
message_text_m11=$(echo "$m11")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vless-reality-vision Поделиться ссылкой 】：поддерживатьnekobox "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/s-box/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws Поделиться ссылкой 】：поддерживатьv2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/s-box/vm_ws_argols.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo临时域名Поделиться ссылкой 】：поддерживатьv2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/s-box/vm_ws_argogd.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+ArgoФиксированное доменное имяПоделиться ссылкой 】：поддерживатьv2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3_5}")
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws-tls Поделиться ссылкой 】：поддерживатьv2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Hysteria-2 Поделиться ссылкой 】：поддерживатьnekobox "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Tuic-v5 Поделиться ссылкой 】：поддерживатьnekobox "$'"'"'\n\n'"'"'"${message_text_m6}")

if [[ -f /etc/s-box/sing_box_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 订阅链接 】：поддерживатьSFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m9}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 配置文件(4段) 】：поддерживатьSFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5_5}")
fi

if [[ -f /etc/s-box/clash_meta_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 订阅链接 】：поддерживатьClash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m10}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 配置文件(2段) 】：поддерживатьClash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m8}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m8_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 四合一протокол聚合订阅链接 】：поддерживатьnekobox "$'"'"'\n\n'"'"'"${message_text_m11}")

if [ $? == 124 ];then
echo TG_api请求超时,请检查网络是否重启完成并是否能够访问TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "TG推送成功";
else
echo "TG推送失败，请检查TG机器人Token和ID";
fi
' > /etc/s-box/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/s-box/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/s-box/sbtg.sh
green "Настроить完成！请убеждатьсяTG机器人已处于激活状态！"
tgnotice
else
changeserv
fi
}

tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "请稍等5秒，TG机器人准备推送……"
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
yellow "еще нетНастроитьTG通知功能"
fi
exit
}

changeserv(){
sbactive
echo
green "Sing-boxИзменения в конфигурации можно выбрать следующим образом:"
readp "1：Изменение адреса подмены домена Relity、Переключайтесь между самоподписанными сертификатами и сертификатами AcmeСертификат домена、выключательTLS\n2：Заменить полный протоколUUID(пароль)、Vmess-Pathпуть\n3：НастроитьВременный туннель Арго、固定隧道\n4：切换IPV4或IPV6的代理приоритет级\n5：НастроитьTelegram推送节点通知\n6：更换Warp-wireguard出站账户\n7：НастроитьGitlab订阅Поделиться ссылкой\n8：Настроить所有Vmess节点的CDN优选地址\n0：Вернуться на предыдущий уровень\nПожалуйста, выберите【0-8】：" menu
if [ "$menu" = "1" ];then
changeym
elif [ "$menu" = "2" ];then
changeuuid
elif [ "$menu" = "3" ];then
cfargo_ym
elif [ "$menu" = "4" ];then
changeip
elif [ "$menu" = "5" ];then
tgsbshow
elif [ "$menu" = "6" ];then
changewg
elif [ "$menu" = "7" ];then
gitlabsub
elif [ "$menu" = "8" ];then
vmesscfadd
else 
sb
fi
}

vmesscfadd(){
echo
green "В качестве предпочтительного адреса CDN мы рекомендуем использовать стабильные официальные домены CDN от крупных мировых компаний или организаций："
blue "www.visa.com.sg"
blue "www.wto.org"
blue "www.web.com"
echo
yellow "1：ОбычайVmess-ws(tls)主протокол节点的CDN优选地址"
yellow "2：针对选项1，重置客户端host/sni域名(IP解析到CF上的域名)"
yellow "3：ОбычайVmess-ws(tls)-Argo节点的CDN优选地址"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
echo
green "请убеждатьсяVPS的IP已解析到Cloudflare的域名上"
if [[ ! -f /etc/s-box/cfymjx.txt ]] 2>/dev/null; then
readp "输入客户端host/sni域名(IP解析到CF上的域名)：" menu
echo "$menu" > /etc/s-box/cfymjx.txt
fi
echo
readp "输入Обычай的优选IP/域名：" menu
echo "$menu" > /etc/s-box/cfvmadd_local.txt
green "Настроить成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
elif  [ "$menu" = "2" ]; then
rm -rf /etc/s-box/cfymjx.txt
green "重置成功，可选择1重新Настроить" && sleep 2 && vmesscfadd
elif  [ "$menu" = "3" ]; then
readp "输入Обычай的优选IP/域名：" menu
echo "$menu" > /etc/s-box/cfvmadd_argo.txt
green "Настроить成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
else
changeserv
fi
}

gitlabsub(){
echo
green "请убеждатьсяGitlab官网上已建立项目，已开启推送功能，已获取访问令牌"
yellow "1：重置/НастроитьGitlab订阅链接"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
cd /etc/s-box
readp "输入登录邮箱: " email
readp "输入访问令牌: " token
readp "输入用户名: " userid
readp "输入项目名: " project
echo
green "多台VPS共用一个令牌及项目名，可创建多个分支订阅链接"
green "回车跳过表示不新建，только使用主分支main订阅链接(首台VPS建议回车跳过)"
readp "新建分支名称: " gitlabml
echo
if [[ -z "$gitlabml" ]]; then
gitlab_ml=''
git_sk=main
rm -rf /etc/s-box/gitlab_ml_ml
else
gitlab_ml=":${gitlabml}"
git_sk="${gitlabml}"
echo "${gitlab_ml}" > /etc/s-box/gitlab_ml_ml
fi
echo "$token" > /etc/s-box/gitlabtoken.txt
rm -rf /etc/s-box/.git
git init >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git config --global user.email "${email}" >/dev/null 2>&1
git config --global user.name "${userid}" >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
branches=$(git branch)
if [[ $branches == *master* ]]; then
git branch -m master main >/dev/null 2>&1
fi
git remote add origin https://${token}@gitlab.com/${userid}/${project}.git >/dev/null 2>&1
if [[ $(ls -a | grep '^\.git$') ]]; then
cat > /etc/s-box/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sing_box_client.json/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/sing_box_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clash_meta_client.yaml/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/clash_meta_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/jh_sub_gitlab.txt
clsbshow
else
yellow "НастроитьGitlab订阅链接失败，请反馈"
fi
cd
else
changeserv
fi
}

gitlabsubgo(){
cd /etc/s-box
if [[ $(ls -a | grep '^\.git$') ]]; then
if [ -f /etc/s-box/gitlab_ml_ml ]; then
gitlab_ml=$(cat /etc/s-box/gitlab_ml_ml)
fi
git rm --cached sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
clsbshow
else
yellow "еще нетНастроитьGitlab订阅链接"
fi
cd
}

clsbshow(){
green "ТекущийSing-box节点已更新并推送"
green "Sing-box订阅链接如下："
blue "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
green "Sing-box订阅链接二维码如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "ТекущийClash-meta节点配置已更新并推送"
green "Clash-meta订阅链接如下："
blue "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
green "Clash-meta订阅链接二维码如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "Текущий聚合订阅节点配置已更新并推送"
green "订阅链接如下："
blue "$(cat /etc/s-box/jh_sub_gitlab.txt 2>/dev/null)"
echo
yellow "可以在网页上输入订阅链接查看配置内容，如果无配置内容，请自检Gitlab相关Настроить并重置"
echo
}

warpwg(){
warpcode(){
reg(){
keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)
response=$(curl -sL --tlsv1.3 --connect-timeout 3 --max-time 5 \
-X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
-H 'CF-Client-Version: a-7.21-0721' \
-H 'Content-Type: application/json' \
-d '{
"key": "'"$public_key"'",
"tos": "'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"
}')
if [ -z "$response" ]; then
return 1
fi
echo "$response" | python3 -m json.tool 2>/dev/null | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
}
reserved(){
reserved_str=$(echo "$warp_info" | grep 'client_id' | cut -d\" -f4)
reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
echo -e "{\n    \"reserved_dec\": $reserved_dec,"
echo -e "    \"reserved_hex\": \"0x$reserved_hex\","
echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
}
result() {
echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g'
echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g'
echo "}"
}
warp_info=$(reg) 
warp_reserved=$(reserved) 
result
}
output=$(warpcode)
if ! echo "$output" 2>/dev/null | grep -w "private_key" > /dev/null; then
v6=2606:4700:110:860e:738f:b37:f15:d38d
pvk=g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4=
res=[33,217,129]
else
pvk=$(echo "$output" | sed -n 4p | awk '{print $2}' | tr -d ' "' | sed 's/.$//')
v6=$(echo "$output" | sed -n 7p | awk '{print $2}' | tr -d ' "')
res=$(echo "$output" | sed -n 1p | awk -F":" '{print $NF}' | tr -d ' ' | sed 's/.$//')
fi
blue "Private_key私钥：$pvk"
blue "IPV6地址：$v6"
blue "reserved值：$res"
}

changewg(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
if [[ "$sbnh" == "1.10" ]]; then
wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0]')
wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .private_key')
wgres=$(sed -n '165s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server')
wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server_port')
else
wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .address[1] | split("/")[0]')
wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .private_key')
wgres=$(sed -n '125s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].address')
wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].port')
fi
echo
green "Текущийwarp-wireguard可更换的参数如下："
green "Private_key私钥：$wgprkey"
green "IPV6地址：$wgipv6"
green "Reserved值：$wgres"
green "对端IP：$wgip:$wgpo"
echo
yellow "1：更换warp-wireguard账户"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-1】：" menu
if [ "$menu" = "1" ]; then
green "最新随机生成普通warp-wireguard账户如下"
warpwg
echo
readp "输入ОбычайPrivate_key：" menu
sed -i "163s#$wgprkey#$menu#g" /etc/s-box/sb10.json
sed -i "115s#$wgprkey#$menu#g" /etc/s-box/sb11.json
readp "输入ОбычайIPV6地址：" menu
sed -i "161s/$wgipv6/$menu/g" /etc/s-box/sb10.json
sed -i "113s/$wgipv6/$menu/g" /etc/s-box/sb11.json
readp "输入ОбычайReserved值 (格式：数字,数字,数字)，如无值则回车跳过：" menu
if [ -z "$menu" ]; then
menu=0,0,0
fi
sed -i "165s/$wgres/$menu/g" /etc/s-box/sb10.json
sed -i "125s/$wgres/$menu/g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "Настроить结束"
green "可以先在选项5-1或5-2使用完整域名分流：cloudflare.com"
green "然后使用任意节点打开网页https://cloudflare.com/cdn-cgi/trace，查看ТекущийWARP账户类型"
elif  [ "$menu" = "2" ]; then
green "请稍等……更新中……"
if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n2\n") | bash endip.sh > /dev/null 2>&1
nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F "]" '{print $2}' | tr -d ':')
else
curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n1\n") | bash endip.sh > /dev/null 2>&1
nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $1}')
nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $2}')
fi
a=$(cat /root/result.csv 2>/dev/null | awk -F, '$3!="timeout ms" {print} ' | sed -n '2p' | awk -F ',' '{print $2}')
if [[ -z $a || $a = "100.00%" ]]; then
if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
nwgip=2606:4700:d0::a29f:c001
nwgpo=2408
else
nwgip=162.159.192.1
nwgpo=2408
fi
fi
sed -i "157s#$wgip#$nwgip#g" /etc/s-box/sb10.json
sed -i "158s#$wgpo#$nwgpo#g" /etc/s-box/sb10.json
sed -i "118s#$wgip#$nwgip#g" /etc/s-box/sb11.json
sed -i "119s#$wgpo#$nwgpo#g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
rm -rf /root/result.csv /root/endip.sh 
echo
green "优选完毕，Текущий使用的对端IP：$nwgip:$nwgpo"
else
changeserv
fi
}

sbymfl(){
sbport=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}') 
sbport=${sbport:-'40000'}
resv1=$(curl -s --socks5 localhost:$sbport icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$sbport icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
warp_s4_ip='Socks5-IPV4еще нет启动，黑名单模式'
warp_s6_ip='Socks5-IPV6еще нет启动，黑名单模式'
else
warp_s4_ip='Socks5-IPV4可用'
warp_s6_ip='Socks5-IPV6自测'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='无本地IPV4，黑名单模式'      
vps_ipv6="ТекущийIP：$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="ТекущийIP：$v4"    
vps_ipv6="ТекущийIP：$v6"
else
vps_ipv4="ТекущийIP：$v4"    
vps_ipv6='无本地IPV6，黑名单模式'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].domain_suffix | join(" ")')
wg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
if [[ "$wd4" == "yg_kkk" && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【warp出站IPV4可用】еще нет分流${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
fi

wd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].domain_suffix | join(" ")')
wg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
if [[ "$wd6" == "yg_kkk" && ("$wg6" == "yg_kkk"|| -z "$wg6") ]]; then
wfl6="${yellow}【warp出站IPV6自测】еще нет分流${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
fi

sd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].domain_suffix | join(" ")')
sg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】еще нет分流${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
fi

sd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].domain_suffix | join(" ")')
sg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】еще нет分流${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
fi

ad4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].domain_suffix | join(" ")')
ag4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
if [[ "$ad4" == "yg_kkk" && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】еще нет分流${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
fi

ad6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].domain_suffix | join(" ")')
ag6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
if [[ "$ad6" == "yg_kkk" && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】еще нет分流${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
fi
}

changefl(){
sbactive
blue "对所有протокол进行统一的域名分流"
blue "为убеждаться分流可用，双栈IP（IPV4/IPV6）分流模式为приоритет模式"
blue "warp-wireguard默认开启 (选项1与2)"
blue "socks5需要在VPSПожалуйста используйтеитьwarp官方客户端或者WARP-plus-Socks5-赛风VPN (选项3与4)"
blue "VPS本地出站分流(选项5与6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "ТекущийSing-box内核поддерживатьgeosite分流方式" || blue "ТекущийSing-box内核不поддерживатьgeosite分流方式，толькоподдерживать分流2、3、5、6选项"
echo
yellow "注意："
yellow "一、完整域名方式只能填完整域名 (例：谷歌网站填写：www.google.com)"
yellow "二、geosite方式须填写geosite规则名 (例：奈飞填写:netflix ；迪士尼填写:disney ；ChatGPT填写:openai ；全局且绕过中国填写:geolocation-!cn)"
yellow "三、同一个完整域名或者geosite切勿重复分流"
yellow "四、如分流通道中有个别通道无网络，所填分流为黑名单模式，即屏蔽该网站访问"
changef
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
echo
if [[ "$sbnh" != "1.10" ]]; then
wfl4='暂不поддерживать'
sfl6='暂不поддерживать'
fi
green "1：重置warp-wireguard-ipv4приоритетРаспределенные домены $wfl4"
green "2：重置warp-wireguard-ipv6приоритетРаспределенные домены $wfl6"
green "3：重置warp-socks5-ipv4приоритетРаспределенные домены $sfl4"
green "4：重置warp-socks5-ipv6приоритетРаспределенные домены $sfl6"
green "5：重置VPS本地ipv4приоритетРаспределенные домены $adfl4"
green "6：重置VPS本地ipv6приоритетРаспределенные домены $adfl6"
green "0：Вернуться на предыдущий уровень"
echo
readp "Пожалуйста, выберите【0-6】：" menu

if [ "$menu" = "1" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的完整域名方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "184s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的geosite方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "187s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！Текущий暂时只поддерживатьwarp-wireguard-ipv6，如需要warp-wireguard-ipv4，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "2" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的完整域名方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "193s/.*/$w6flym/" /etc/s-box/sb10.json
sed -i "169s/.*/$w6flym/" /etc/s-box/sb11.json
sed -i "181s/.*/$w6flym/" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的geosite方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "196s/.*/$w6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "遗憾！ТекущийSing-box内核不поддерживатьgeosite分流方式。如要поддерживать，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "3" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的完整域名方式的分流通道：" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "202s/.*/$s4flym/" /etc/s-box/sb10.json
sed -i "162s/.*/$s4flym/" /etc/s-box/sb11.json
sed -i "175s/.*/$s4flym/" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的geosite方式的分流通道：" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "205s/.*/$s4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "遗憾！ТекущийSing-box内核不поддерживатьgeosite分流方式。如要поддерживать，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "4" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的完整域名方式的分流通道：" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "211s/.*/$s6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的geosite方式的分流通道：" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "214s/.*/$s6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！Текущий暂时只поддерживатьwarp-socks5-ipv4，如需要warp-socks5-ipv6，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "5" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的完整域名方式的分流通道：" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "220s/.*/$ad4flym/" /etc/s-box/sb10.json
sed -i "188s/.*/$ad4flym/" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的geosite方式的分流通道：" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "223s/.*/$ad4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "遗憾！ТекущийSing-box内核不поддерживатьgeosite分流方式。如要поддерживать，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "6" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：Вернуться на предыдущий уровень\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的完整域名方式的分流通道：" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "229s/.*/$ad6flym/" /etc/s-box/sb10.json
sed -i "194s/.*/$ad6flym/" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的geosite方式的分流通道：" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "232s/.*/$ad6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "遗憾！ТекущийSing-box内核不поддерживатьgeosite分流方式。如要поддерживать，请切换1.10系列内核" && exit
fi
else
changef
fi
else
sb
fi
}

restartsb(){
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box restart
else
systemctl enable sing-box
systemctl start sing-box
systemctl restart sing-box
fi
}

stclre(){
if [[ ! -f '/etc/s-box/sb.json' ]]; then
red "еще нет正常Пожалуйста используйтеитьSing-box" && exit
fi
readp "1：重启\n2：关闭\nПожалуйста, выберите：" menu
if [ "$menu" = "1" ]; then
restartsb
sbactive
green "Sing-box服务已重启\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
else
systemctl stop sing-box
systemctl disable sing-box
fi
green "Sing-box服务已关闭\n" && sleep 3 && sb
else
stclre
fi
}

cronsb(){
uncronsb
crontab -l > /tmp/crontab.tmp
echo "0 1 * * * systemctl restart sing-box;rc-service sing-box restart" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
uncronsb(){
crontab -l > /tmp/crontab.tmp
sed -i '/sing-box/d' /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}

lnsb(){
rm -rf /usr/bin/sb
curl -L -o /usr/bin/sb -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh
chmod +x /usr/bin/sb
}

upsbyg(){
if [[ ! -f '/usr/bin/sb' ]]; then
red "еще нет正常Пожалуйста используйтеитьSing-box-yg" && exit
fi
lnsb
curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "Обновить контент" '{print $1}' | head -n 1 > /etc/s-box/v
green "Sing-box-ygПожалуйста используйтеить脚本升级成功" && sleep 5 && sb
}

lapre(){
latcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
precore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【已Пожалуйста используйтеитьv$inscore】" || pre="【已Пожалуйста используйтеитьv$inscore】"
green "1：升级/切换Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
green "2：升级/切换Sing-box最新测试版 v$precore  ${bblue}${pre}${plain}"
green "3：切换Sing-box某个正式版或测试版，需指定版本号 (建议1.10.0以上版本)"
green "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
elif [ "$menu" = "3" ]; then
echo
red "注意: 版本号在 https://github.com/SagerNet/sing-box/tags 可查，且有Downloads字样 (必须1.10.0以上版本)"
green "正式版版本号格式：数字.数字.数字 (例：1.10.7   注意，1.10系列内核поддерживатьgeosite分流，1.10以上内核不поддерживатьgeosite分流"
green "测试版版本号格式：数字.数字.数字-alpha或rc或beta.数字 (例：1.10.0-alpha或rc或beta.1)"
readp "Пожалуйста, введитеSing-box版本号：" upcore
else
sb
fi
if [[ -n $upcore ]]; then
green "开始下载并更新Sing-box内核……请稍等"
sbname="sing-box-$upcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
blue "Успешно обновлена/переключена версия ядра Sing-box.：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 3 && sb
else
red "Загрузка ядра Sing-box не завершена.，Пожалуйста используйтеитьНе удалось, пожалуйста, попробуйте еще раз." && upsbcroe
fi
else
red "Загрузка ядра Sing-box не удалась или оно отсутствует. Пожалуйста, попробуйте еще раз." && upsbcroe
fi
else
red "Ошибка определения номера версии, пожалуйста, попробуйте еще раз." && upsbcroe
fi
}

unins(){
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
rc-update del sing-box default
rm /etc/init.d/sing-box -f
else
systemctl stop sing-box >/dev/null 2>&1
systemctl disable sing-box >/dev/null 2>&1
rm -f /etc/systemd/system/sing-box.service
fi
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geoip.db /root/geosite.db /root/warpapi /root/warpip
uncronsb
iptables -t nat -F PREROUTING >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
green "Sing-box卸载完成！"
blue "欢迎继续使用Sing-box-yg脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)"
echo
}

sblog(){
red "退出日志 Ctrl+c"
if [[ x"${release}" == x"alpine" ]]; then
yellow "暂不поддерживатьalpine查看日志"
else
#systemctl status sing-box
journalctl -u sing-box.service -o cat -f
fi
}

sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "еще нет正常启动Sing-box，请卸载重装或者选择10查看运行日志反馈" && exit
fi
}

sbshare(){
rm -rf /etc/s-box/jhdy.txt /etc/s-box/vl_reality.txt /etc/s-box/vm_ws_argols.txt /etc/s-box/vm_ws_argogd.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt /etc/s-box/hy2.txt /etc/s-box/tuic5.txt
result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5
cat /etc/s-box/vl_reality.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argols.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_tls.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/hy2.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/tuic5.txt 2>/dev/null >> /etc/s-box/jhdy.txt
baseurl=$(base64 -w 0 < /etc/s-box/jhdy.txt 2>/dev/null)
v2sub=$(cat /etc/s-box/jhdy.txt 2>/dev/null)
echo "$v2sub" > /etc/s-box/jh_sub.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 四合一聚合订阅 】节点信息如下：" && sleep 2
echo
echo "Поделиться ссылкой"
echo -e "${yellow}$baseurl${plain}"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
sb_client
}

clash_sb_share(){
sbactive
echo
yellow "1：刷新并查看各протоколПоделиться ссылкой、二维码、四合一聚合订阅"
yellow "2：刷新并查看Clash-Meta、Sing-box客户端SFA/SFI/SFW三合一配置、Gitlab私有订阅链接"
yellow "3：刷新并查看Hysteria2、Tuic5的V2rayN客户端Обычай配置"
yellow "4：推送最新节点配置信息(选项1+选项2)到Telegram通知"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-4】：" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "请稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "Gitlab订阅链接如下："
gitlabsubgo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】Clash-Meta配置文件显示如下："
red "文件目录 /etc/s-box/clash_meta_client.yaml ，复制自建以yaml文件格式为准" && sleep 2
echo
cat /etc/s-box/clash_meta_client.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】SFA/SFI/SFW配置文件显示如下："
red "安卓SFA、苹果SFI，win电脑官方文件包SFW请到甬哥Github项目自行下载，"
red "文件目录 /etc/s-box/sing_box_client.json ，复制自建以json文件格式为准" && sleep 2
echo
cat /etc/s-box/sing_box_client.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
elif  [ "$menu" = "3" ]; then
green "请稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Hysteria-2 】ОбычайV2rayN配置文件显示如下："
red "文件目录 /etc/s-box/v2rayn_hy2.yaml ，复制自建以yaml文件格式为准" && sleep 2
echo
cat /etc/s-box/v2rayn_hy2.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
red "注意：V2rayN客户端使用ОбычайTuic5官方客户端核心时，不поддерживатьTuic5自签证书，толькоподдерживатьСертификат домена" && sleep 2
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
else
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Tuic-v5 】ОбычайV2rayN配置文件显示如下："
red "文件目录 /etc/s-box/v2rayn_tu5.json ，复制自建以json文件格式为准" && sleep 2
echo
cat /etc/s-box/v2rayn_tu5.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
fi
elif [ "$menu" = "4" ]; then
tgnotice
else
sb
fi
}

acme(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
}
cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "ТекущийVPS的架构为 $vi，不поддерживать开启原版BBR加速" && sleep 2 && exit 
else
green "点击任意键，即可开启BBR加速，ctrl+c退出"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

showprotocol(){
allports
sbymfl
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) || -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
vm_zs="TLS关闭"
argoym="已开启"
else
vm_zs="TLS关闭"
argoym="еще нет开启"
fi
else
vm_zs="TLS开启"
argoym="不поддерживать开启"
fi
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="自签证书" || hy2_zs="Сертификат домена"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="自签证书" || tu5_zs="Сертификат домена"
echo -e "Sing-box节点关键信息、已Распределенные домены情况如下："
echo -e "🚀【 Vless-reality 】${yellow}порт:$vl_port  RealityСертификат домена伪装地址：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【   Vmess-ws    】${yellow}порт:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
else
echo -e "🚀【 Vmess-ws-tls  】${yellow}порт:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
fi
echo -e "🚀【  Hysteria-2   】${yellow}порт:$hy2_port  证书形式:$hy2_zs  转发多порт: $hy2zfport${plain}"
echo -e "🚀【    Tuic-v5    】${yellow}порт:$tu5_port  证书形式:$tu5_zs  转发多порт: $tu5zfport${plain}"
if [ "$argoym" = "已开启" ]; then
echo -e "Vmess-UUID：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')${plain}"
echo -e "Vmess-Path：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')${plain}"
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo -e "Argo临时域名：${yellow}$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
echo -e "ArgoФиксированное доменное имя：${yellow}$(cat /etc/s-box/sbargoym.log 2>/dev/null)${plain}"
fi
fi
echo "------------------------------------------------------------------------------------"
if [[ -n $(ps -e | grep sbwpph) ]]; then
s5port=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}'| awk -F":" '{print $NF}')
s5gj=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $6}')
case "$s5gj" in
AT) showgj="Австрия" ;;
AU) showgj="Австралия" ;;
BE) showgj="比利时" ;;
BG) showgj="保加利亚" ;;
CA) showgj="加拿大" ;;
CH) showgj="瑞士" ;;
CZ) showgj="捷克" ;;
DE) showgj="德国" ;;
DK) showgj="丹麦" ;;
EE) showgj="爱沙尼亚" ;;
ES) showgj="西班牙" ;;
FI) showgj="芬兰" ;;
FR) showgj="法国" ;;
GB) showgj="英国" ;;
HR) showgj="克罗地亚" ;;
HU) showgj="匈牙利" ;;
IE) showgj="爱尔兰" ;;
IN) showgj="印度" ;;
IT) showgj="意大利" ;;
JP) showgj="日本" ;;
LT) showgj="立陶宛" ;;
LV) showgj="拉脱维亚" ;;
NL) showgj="荷兰" ;;
NO) showgj="挪威" ;;
PL) showgj="波兰" ;;
PT) showgj="葡萄牙" ;;
RO) showgj="罗马尼亚" ;;
RS) showgj="塞尔维亚" ;;
SE) showgj="瑞典" ;;
SG) showgj="新加坡" ;;
SK) showgj="斯洛伐克" ;;
US) showgj="美国" ;;
esac
grep -q "country" /etc/s-box/sbwpph.log 2>/dev/null && s5ms="多地区Psiphon代理模式 (порт:$s5port  国家:$showgj)" || s5ms="本地Warp代理模式 (порт:$s5port)"
echo -e "WARP-plus-Socks5状态：$yellow已启动 $s5ms$plain"
else
echo -e "WARP-plus-Socks5状态：$yellowеще нет启动$plain"
fi
echo "------------------------------------------------------------------------------------"
ww4="warp-wireguard-ipv4приоритетРаспределенные домены：$wfl4"
ww6="warp-wireguard-ipv6приоритетРаспределенные домены：$wfl6"
ws4="warp-socks5-ipv4приоритетРаспределенные домены：$sfl4"
ws6="warp-socks5-ipv6приоритетРаспределенные домены：$sfl6"
l4="VPS本地ipv4приоритетРаспределенные домены：$adfl4"
l6="VPS本地ipv6приоритетРаспределенные домены：$adfl6"
[[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
for ymfl in "${ymflzu[@]}"; do
if [[ ${!ymfl} != *"еще нет"* ]]; then
echo -e "${!ymfl}"
fi
done
if [[ $ww4 = *"еще нет"* && $ww6 = *"еще нет"* && $ws4 = *"еще нет"* && $ws6 = *"еще нет"* && $l4 = *"еще нет"* && $l6 = *"еще нет"* ]] ; then
echo -e "Разделение доменных имен не настроено."
fi
}

inssbwpph(){
sbactive
ins(){
if [ ! -e /etc/s-box/sbwpph ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/sbwpph -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sbwpph_$cpu
chmod +x /etc/s-box/sbwpph
fi
if [[ -n $(ps -e | grep sbwpph) ]]; then
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
fi
v4v6
if [[ -n $v4 ]]; then
sw46=4
else
red "IPV4Не существует，убеждаться пожалуйста используйтеить через режим WARP-IPv4"
sw46=6
fi
echo
readp "Установите значение параметра WARP-plus-Socks5 равным (нажмите Enter, чтобы перейти к значению по умолчанию 40000).：" port
if [[ -z $port ]]; then
port=40000
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nпорт被占用，请重新输入порт" && readp "Обычайпорт:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\nпорт被占用，请重新输入порт" && readp "Обычайпорт:" port
done
fi
s5port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sed -i "127s/$s5port/$port/g" /etc/s-box/sb10.json
sed -i "150s/$s5port/$port/g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
}
unins(){
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box/sbwpph.log /etc/s-box/sbwpphid.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
echo
yellow "1：Сбросить и включить локальный режим прокси Warp-plus-Socks5."
yellow "2：Сбросьте настройки и включите многорегиональный режим прокси Psiphon для WARP-plus-Socks5."
yellow "3：Остановить режим прокси WARP-plus-Socks5"
yellow "0：Вернуться на предыдущий уровень"
readp "Пожалуйста, выберите【0-3】：" menu
if [ "$menu" = "1" ]; then
ins
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "Запрошен IP-адрес... Пожалуйста, подождите..." && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "IP-адрес WARP-plus-Socks5 успешно получен; теперь возможно распределение трафика через прокси Socks5."
fi
elif [ "$menu" = "2" ]; then
ins
echo '
Австрия（AT）
Австралия（AU）
比利时（BE）
保加利亚（BG）
加拿大（CA）
瑞士（CH）
捷克 (CZ)
德国（DE）
丹麦（DK）
爱沙尼亚（EE）
西班牙（ES）
芬兰（FI）
法国（FR）
英国（GB）
克罗地亚（HR）
匈牙利 (HU)
爱尔兰（IE）
印度（IN）
意大利 (IT)
日本（JP）
立陶宛（LT）
拉脱维亚（LV）
荷兰（NL）
挪威 (NO)
波兰（PL）
葡萄牙（PT）
罗马尼亚 (RO)
塞尔维亚（RS）
瑞典（SE）
新加坡 (SG)
斯洛伐克（SK）
美国（US）
'
readp "Вы можете выбрать страну/регион (введите две последние заглавные буквы, например, US для обозначения Соединенных Штатов).：" guojia
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "Запрошен IP-адрес... Пожалуйста, подождите..." && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "IP-адрес WARP-plus-Socks5 успешно получен; теперь возможно распределение трафика через прокси Socks5."
fi
elif [ "$menu" = "3" ]; then
unins && green "Функция прокси WARP-plus-Socks5 прекращена"
else
sb
fi
}

sbsm(){
echo
green "Подпишитесь на YouTube-канал Ён Ге.：https://youtube.com/@ygkkk?sub_confirmation=1 Будьте в курсе последних новостей о соглашениях о представительстве и методах их обхода."
echo
blue "sing-box-ygВидеоурок по написанию сценария：https://www.youtube.com/playlist?list=PLMgly2AulGG_Affv6skQXWnVqw7XWiPwJ"
echo
blue "sing-box-ygОписание скрипта в блоге：http://ygkkk.blogspot.com/2023/10/sing-box-yg.html"
echo
blue "sing-box-ygАдрес проекта сценария：https://github.com/yonggekkk/sing-box-yg"
echo
blue "Рекомендуемый новый продукт от Yongge: ArgoSB — неинтерактивный мини-скрипт, запускаемый одним щелчком мыши."
blue "поддерживать：AnyTLS、Any-reality、Vless-xhttp-reality、Vless-reality-vision、Shadowsocks-2022、Hysteria2、Tuic、Vmess-ws、Argo临时/固定隧道"
blue "Адрес проекта ArgoSB：https://github.com/yonggekkk/ArgoSB"
echo
}

clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "甬哥Github项目  ：github.com/yonggekkk"
white "甬哥Blogger博客 ：ygkkk.blogspot.com"
white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "Vless-reality-vision、Vmess-ws(tls)+Argo、Hysteria-2、Tuic-v5 Четырехпротокольный сценарий сосуществования"
white "Ярлык скрипта：sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 一键Пожалуйста используйтеить Sing-box" 
green " 2. 删除卸载 Sing-box"
white "----------------------------------------------------------------------------------"
green " 3. 变更配置 【双证书TLS/UUIDпуть/Argo/IPприоритет/TG通知/Warp/订阅/CDN优选】" 
green " 4. 更改主порт/添加多порт跳跃复用" 
green " 5. 三通道域名分流"
green " 6. 关闭/重启 Sing-box"   
green " 7. 更新 Sing-box-yg 脚本"
green " 8. 更新/切换/指定 Sing-box версия ядра"
white "----------------------------------------------------------------------------------"
green " 9. 刷新并查看节点 【Clash-Meta/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】"
green "10. 查看 Sing-box 运行日志"
green "11. 一键原版BBR+FQ加速"
green "12. 管理 Acme 申请Сертификат домена"
green "13. 管理 Warp 查看Netflix/ChatGPT解锁情况"
green "14. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】"
green "15. 刷新本地IP、切换IPV4/IPV6配置输出"
white "----------------------------------------------------------------------------------"
green "16. Sing-box-yg脚本使用说明书"
white "----------------------------------------------------------------------------------"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "Обновить контент" '{print $1}' | head -n 1)
if [ -f /etc/s-box/v ]; then
if [ "$insV" = "$latestV" ]; then
echo -e "Последняя версия текущего скрипта Sing-box-yg：${bblue}${insV}${plain} (已Пожалуйста используйтеить)"
else
echo -e "Текущий Sing-box-yg номер версии скрипта：${bblue}${insV}${plain}"
echo -e "Последнее обнаруженное Sing-box-yg номер версии скрипта：${yellow}${latestV}${plain} (可选择7进行更新)"
echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version)${plain}"
fi
else
echo -e "Текущий Sing-box-yg номер версии скрипта：${bblue}${latestV}${plain}"
yellow "еще нетПожалуйста используйтеить Sing-box-yg 脚本！请先选择 1 Пожалуйста используйтеить"
fi

lapre
if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "Текущий Sing-box 最新正式版内核：${bblue}${inscore}${plain} (已Пожалуйста используйтеить)"
echo
echo -e "Текущий Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
else
echo
echo -e "Текущий Sing-box 已Пожалуйста используйтеить正式版内核：${bblue}${inscore}${plain}"
echo -e "Последнее обнаруженное Sing-box 正式版内核：${yellow}${latcore}${plain} (可选择8进行更新)"
echo
echo -e "Текущий Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "Текущий Sing-box 最新测试版内核：${bblue}${inscore}${plain} (已Пожалуйста используйтеить)"
echo
echo -e "Текущий Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
else
echo
echo -e "Текущий Sing-box 已Пожалуйста используйтеить测试版内核：${bblue}${inscore}${plain}"
echo -e "Последнее обнаруженное Sing-box 测试版内核：${yellow}${precore}${plain} (可选择8进行更新)"
echo
echo -e "Текущий Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
fi
fi
else
echo
echo -e "Текущий Sing-box 最新正式版内核：${bblue}${latcore}${plain}"
echo -e "Текущий Sing-box 最新测试版内核：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS状态如下："
echo -e "系统:$blue$op$plain  \c";echo -e "内核:$blue$version$plain  \c";echo -e "处理器:$blue$cpu$plain  \c";echo -e "虚拟化:$blue$vi$plain  \c";echo -e "BBR算法:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
rpip=$(sed 's://.*::g' /etc/s-box/sb.json 2>/dev/null | jq -r '.outbounds[0].domain_strategy')
[[ -z $v4 ]] && showv4='IPV4地址丢失，请切换至IPV6或者重装Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='IPV6地址丢失，请切换至IPV4或者重装Sing-box' || showv6=$v6$w6
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="IPV6приоритет出站($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="IPV4приоритет出站($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="толькоIPV4出站($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="толькоIPV6出站($showv6)"
fi
if [[ -z $v4 ]]; then
vps_ipv4='无IPV4'      
vps_ipv6="$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
else
vps_ipv4="$v4"    
vps_ipv6='无IPV6'
fi
echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
if [[ -n $rpip ]]; then
echo -e "代理IPприоритет级：$blue$v4_6$plain"
fi
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$blue运行中$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$yellowеще нет启动，选择10查看日志并反馈，建议切换正式版内核或卸载重装脚本$plain"
else
echo -e "Sing-box状态：$redеще нетПожалуйста используйтеить$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "Пожалуйста, введите数字【0-16】:" Input
case "$Input" in  
 1 ) instsllsingbox;;
 2 ) unins;;
 3 ) changeserv;;
 4 ) changeport;;
 5 ) changefl;;
 6 ) stclre;;
 7 ) upsbyg;; 
 8 ) upsbcroe;;
 9 ) clash_sb_share;;
10 ) sblog;;
11 ) bbr;;
12 ) acme;;
13 ) cfwarp;;
14 ) inssbwpph;;
15 ) wgcfgo && sbshare;;
16 ) sbsm;;
 * ) exit 
esac
