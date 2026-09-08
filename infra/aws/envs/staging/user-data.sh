#!/bin/bash
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl nginx unzip

if ! id parago >/dev/null 2>&1; then
  useradd --system --home /opt/parago --shell /usr/sbin/nologin parago
fi

mkdir -p /etc/parago /opt/parago/releases /opt/parago/shared /var/log/parago
chown -R parago:parago /opt/parago /var/log/parago
chmod 0750 /etc/parago /opt/parago /opt/parago/releases /opt/parago/shared

install -m 0600 -o root -g root /dev/null /etc/parago/parago.env

cat >/etc/nginx/sites-available/parago <<'NGINX'
upstream parago_api {
    server 127.0.0.1:5000;
    keepalive 32;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # CloudFront VPC origin ENIs use private addresses. The security group limits
    # ingress to CloudFront and the per-distribution secret rejects other origins.
    set_real_ip_from __TRUSTED_VPC_CIDR__;
    real_ip_header X-Forwarded-For;
    real_ip_recursive off;
    client_max_body_size 12m;
    client_body_timeout 15s;
    keepalive_timeout 65s;
    send_timeout 30s;

    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    if ($http_x_parago_origin != "__ORIGIN_SECRET__") {
        return 403;
    }

    location /socket.io/ {
        proxy_pass http://parago_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP "";
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 75s;
        proxy_send_timeout 30s;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://parago_api;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP "";
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/parago /etc/nginx/sites-enabled/parago
nginx -t
systemctl enable --now nginx
