#!/bin/bash

if [ "$(id -u)" != "0" ]; then
   echo "Need root access" 1>&2
   exit 1
fiSetup.bash

sudo apt update && sudo apt install -y nginx
sudo systemctl start nginx

mkdir -p /home/vpsadmin/www/webpage/

cat <<EOF > /home/vpsadmin/www/webpage/index.html
<html lang="">
  <head>
    <title>Enter a title, displayed at the top of the window.</title>
  </head>
  <body>
    <h1>Enter the main heading, usually the same as the title.</h1>
    <p>Be <b>bold</b> in stating your key points. Put them in a list:</p>
    <ul>
      <li>The first item in your list</li>
      <li>The second item; <i>italicize</i> key words</li>
    </ul>
    <p>Improve your image by including an image.</p>
    <p>Add a link to your favorite.</p>
    <hr />
    <p>Finally, link to <a href="page2.html">another page</a> in your own Web site.</p>
    <p>&#169; Wiley Publishing, 2011</p>
  </body>
</html>
EOF

echo "Please input your domain："
read user_domain

sudo sed -i "17i \
server {\n\
    listen 80;\n\
    server_name $user_domain;\n\
    root /home/vpsadmin/www/webpage;\n\
    index index.html;\n\
    }" /etc/nginx/nginx.conf

sudo systemctl reload nginx

echo "Nginx has been set up and reload."

wget -O -  https://get.acme.sh | sh
. .bashrc
acme.sh --upgrade --auto-upgrade
acme.sh --set-default-ca --server letsencrypt
acme.sh --issue -d $user_domain -w /home/vpsadmin/www/webpage --keylength ec-256 --force
wget https://github.com/XTLS/Xray-install/raw/main/install-release.sh
sudo bash install-release.sh
rm ~/install-release.sh
mkdir ~/xray_cert
acme.sh --install-cert -d $user_domain --ecc \--fullchain-file ~/xray_cert/xray.crt \--key-file ~/xray_cert/xray.key
chmod +r ~/xray_cert/xray.key
cat <<EOF > ~/xray_cert/xray-cert-renew.sh
#!/bin/bash

/home/vpsadmin/.acme.sh/acme.sh --install-cert -d $user_domain --ecc --fullchain-file /home/vpsadmin/xray_cert/xray.crt --key-file /home/vpsadmin/xray_cert/xray.key
echo "Xray Certificates Renewed"

chmod +r /home/vpsadmin/xray_cert/xray.key
echo "Read Permission Granted for Private Key"

sudo systemctl restart xray
echo "Xray Restarted"
EOF

chmod +x ~/xray_cert/xray-cert-renew.sh

echo "Job added"

CRON_JOB="0 1 1 * *   bash /home/vpsadmin/xray_cert/xray-cert-renew.sh"

( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -

echo "Job added: $CRON_JOB"
xray uuid
mkdir ~/xray_log
touch ~/xray_log/access.log && touch ~/xray_log/error.log
chmod a+w ~/xray_log/*.log
sudo apt-get install -y uuid-runtime
UUID=$(uuidgen)
echo "Your UUID: $UUID"
cat << EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning", 
    "access": "/home/vpsadmin/xray_log/access.log", 
    "error": "/home/vpsadmin/xray_log/error.log" 
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query", 
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block" 
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all"
        ],
        "outboundTag": "block" 
      }
    ]
  },

  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "vpsadmin@yourdomain.com"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80 
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": "http/1.1",
          "certificates": [
            {
              "certificateFile": "/home/vpsadmin/xray_cert/xray.crt",
              "keyFile": "/home/vpsadmin/xray_cert/xray.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF

sudo systemctl start xray

echo "Xray set up finished"
status=$(sudo systemctl is-active xray)

URL="$user_domain"

curl -o /dev/null -s $URL
if [ $? -ne 0 ]; then
    echo "Failed to load webpage"
else
    STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" $URL)

    XRAY_STATUS=$(sudo systemctl is-active xray)

    if [ "$STATUS_CODE" -eq 200 ] && [ "$XRAY_STATUS" == "active" ]; then
      echo "Success"
    else
      if [ "$STATUS_CODE" -ne 200 ]; then
        echo "Failed $STATUS_CODE"
      fi
      if [ "$XRAY_STATUS" != "active" ]; then
        echo "Xray isn't running"
      fi
    fi
fi