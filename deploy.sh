#!/usr/bin/env bash
# Web B2B 一键部署脚本 (Ubuntu/Debian)
# 用法: sudo bash deploy.sh [domain]
#   domain 可选；不传默认 localhost
# 重复运行安全（幂等）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载 .env（如果存在）
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

# 参数: deploy.sh [domain]
# 环境变量:
#   ENABLE_HTTPS=1   启用 Let's Encrypt 自动签证书（需要独立公网 IP 与 80/443 可达）
#   ADMIN_EMAIL=...  与 ENABLE_HTTPS 配套使用，certbot 联系邮箱
#   ADMIN_RESET_PASS 明文重置后台密码（role=1），不传进入交互询问
#   ADMIN_RESET_SKIP=1  强制跳过重置
DOMAIN="${1:-${DOMAIN:-localhost}}"
DB_NAME="${DB_NAME:-python_db}"
DB_USER="${DB_USER:-b2b}"
DB_PASS="${DB_PASS:-}"

# 如果密码未设，生成随机密码
if [[ -z "$DB_PASS" ]]; then
    DB_PASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
    warn_pw_generated=1
fi
ENABLE_HTTPS="${ENABLE_HTTPS:-0}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_RESET_PASS="${ADMIN_RESET_PASS:-}"
ADMIN_RESET_SKIP="${ADMIN_RESET_SKIP:-0}"

# 启用 HTTPS 时默认走 80（+ 443 重定向）；否则默认 8080
if [[ "$ENABLE_HTTPS" == "1" ]]; then
    NGINX_PORT="${NGINX_PORT:-80}"
else
    NGINX_PORT="${NGINX_PORT:-8080}"
fi

TARGET_DIR="${TARGET_DIR:-$SCRIPT_DIR}"
RUN_USER="${SUDO_USER:-${USER}}"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "请用 sudo 运行：sudo bash deploy.sh"
[[ -d "$TARGET_DIR/server" && -d "$TARGET_DIR/web" ]] || fail "未找到 server/ 和 web/ 目录（在 $TARGET_DIR）"
id "$RUN_USER" >/dev/null 2>&1 || fail "用户 $RUN_USER 不存在"

if [[ "$ENABLE_HTTPS" == "1" ]]; then
    [[ "$DOMAIN" != "localhost" && "$DOMAIN" != "127.0.0.1" ]] || fail "ENABLE_HTTPS=1 需要传入真实域名"
    if [[ -z "$ADMIN_EMAIL" ]]; then
        if [[ -t 0 ]]; then
            read -rp "请输入 Let's Encrypt 联系邮箱: " ADMIN_EMAIL
        fi
        [[ -n "$ADMIN_EMAIL" ]] || fail "ENABLE_HTTPS=1 需要提供 ADMIN_EMAIL。可使用 ADMIN_EMAIL=you@example.com 环境变量"
    fi
fi

log "使用变量:"
echo "  TARGET_DIR=$TARGET_DIR"
echo "  RUN_USER=$RUN_USER"
echo "  DOMAIN=$DOMAIN  NGINX_PORT=$NGINX_PORT"
echo "  DB=$DB_NAME / $DB_USER / ${DB_PASS:0:3}******"
if [[ "${warn_pw_generated:-0}" == "1" ]]; then
    warn "未提供 DB_PASS，已自动生成随机密码。保存到 .env 以便后续复用"
    if [[ ! -f "$TARGET_DIR/.env" ]]; then
        cat > "$TARGET_DIR/.env" <<EOF
DOMAIN=$DOMAIN
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
NGINX_PORT=$NGINX_PORT
EOF
        chmod 600 "$TARGET_DIR/.env"
        chown "$RUN_USER:$RUN_USER" "$TARGET_DIR/.env"
        log "已写入 $TARGET_DIR/.env (权限 600)"
    fi
fi
echo

# ---- 1. 系统依赖 ----
log "安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    mariadb-server \
    python3 python3-venv python3-dev \
    libmariadb-dev pkg-config build-essential \
    libjpeg-dev zlib1g-dev libpng-dev libfreetype-dev \
    nginx curl ca-certificates gnupg >/dev/null

# Node.js 18 (如果未安装)
if ! command -v node >/dev/null || [[ "$(node -v 2>/dev/null | cut -dv -f2 | cut -d. -f1)" -lt 18 ]]; then
    log "安装 Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null
    apt-get install -y -qq nodejs >/dev/null
fi
log "Node $(node -v) / npm $(npm -v) / Python $(python3 --version)"

# ---- 2. 数据库 ----
log "启动 MariaDB..."
systemctl enable --now mariadb >/dev/null 2>&1

log "创建数据库与用户..."
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

NEED_IMPORT=1
if mysql "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | grep -q b_user; then
    NEED_IMPORT=0
    warn "数据库已存在 b_user 表，跳过导入 SQL"
fi

if [[ $NEED_IMPORT -eq 1 ]]; then
    SQL_FILE="$TARGET_DIR/web_b2b.sql"
    [[ -f "$SQL_FILE" ]] || fail "找不到 $SQL_FILE"
    log "导入 SQL ($SQL_FILE)..."
    mysql "$DB_NAME" < "$SQL_FILE"
fi

# ---- 3. 后端 ----
log "创建 Python venv 并安装依赖..."
sudo -u "$RUN_USER" bash -c "
  cd '$TARGET_DIR/server'
  [[ -d .venv ]] || python3 -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip -q
  pip install -q Django==3.2.25 PyMySQL==1.0.2 djangorestframework==3.14.0 \
      django-cors-headers==3.13.0 Pillow django-environ==0.10.0
"

log "配置 Django settings.py..."
SETTINGS="$TARGET_DIR/server/server/settings.py"
python3 - "$SETTINGS" "$DB_NAME" "$DB_USER" "$DB_PASS" "$DOMAIN" <<'PY'
import re, sys
p, db_name, db_user, db_pass, domain = sys.argv[1:]
s = open(p).read()
s = re.sub(r"ALLOWED_HOSTS\s*=\s*\[[^\]]*\]", "ALLOWED_HOSTS = ['*']", s, count=1)
s = re.sub(r"'NAME':\s*'[^']*',\s*\n\s*'USER':\s*'[^']*',\s*\n\s*'PASSWORD':\s*'[^']*',",
           f"'NAME': '{db_name}',\n        'USER': '{db_user}',\n        'PASSWORD': '{db_pass}',", s, count=1)
s = re.sub(r"CORS_ORIGIN_ALLOW_ALL\s*=\s*\w+", "CORS_ORIGIN_ALLOW_ALL = True", s)
s = re.sub(r"CORS_ALLOW_ALL_ORIGINS\s*=\s*\w+", "CORS_ALLOW_ALL_ORIGINS = True", s)
proto = 'https' if domain not in ('localhost','127.0.0.1') else 'http'
s = re.sub(r"BASE_HOST_URL\s*=\s*'[^']*'", f"BASE_HOST_URL = '{proto}://{domain}'", s)
open(p,'w').write(s)
print('settings.py 已更新')
PY

# ---- 4. 前端 ----
log "配置 Next.js .env..."
cat > "$TARGET_DIR/web/.env" <<EOF
NEXT_PUBLIC_HOST=$DOMAIN
NEXT_PUBLIC_BASE_URL=
NEXT_PUBLIC_DJANGO_BASE_URL=http://127.0.0.1:8000
NEXT_PUBLIC_BASE_PATH=
NEXT_PUBLIC_TEMPLATE_ID=010
EOF
chown "$RUN_USER:$RUN_USER" "$TARGET_DIR/web/.env"

# 确保 next.config.mjs 包含 rewrites
NEXTCFG="$TARGET_DIR/web/next.config.mjs"
if ! grep -q 'rewrites' "$NEXTCFG"; then
    log "插入 Next.js rewrites 配置..."
    sed -i "s|poweredByHeader: false,|poweredByHeader: false,\n    async rewrites() { return [{source:'/myapp/:path*',destination:'http://127.0.0.1:8000/myapp/:path*'},{source:'/upload/:path*',destination:'http://127.0.0.1:8000/upload/:path*'}]; },|" "$NEXTCFG"
fi

log "安装前端依赖并构建..."
sudo -u "$RUN_USER" bash -c "
  cd '$TARGET_DIR/web'
  npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund
  npm run build
"

# ---- 5. 权限 ----
log "修正上传目录权限 (让 nginx 可访问)..."
# 逐级允许其他用户穿越到 upload
DIR="$TARGET_DIR/server/upload"
while [[ "$DIR" != "/" ]]; do
    chmod o+x "$DIR" 2>/dev/null || true
    DIR="$(dirname "$DIR")"
done
find "$TARGET_DIR/server/upload" -type d -exec chmod o+rx {} \; 2>/dev/null || true
find "$TARGET_DIR/server/upload" -type f -exec chmod o+r {} \; 2>/dev/null || true

# ---- 6. 重置管理员密码（交互式，默认不重置）----
ADMIN_RESET_FINAL_PASS=""
if [[ "$ADMIN_RESET_SKIP" == "1" ]]; then
    warn "已跳过管理员密码重置 (ADMIN_RESET_SKIP=1)"
elif [[ -n "$ADMIN_RESET_PASS" ]]; then
    ADMIN_RESET_FINAL_PASS="$ADMIN_RESET_PASS"
elif [[ -t 0 ]]; then
    echo
    read -rp "是否重置后台管理员密码 (admin111 / admin) ? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        while :; do
            read -rsp "  输入新密码: " p1; echo
            read -rsp "  再输一次确认: " p2; echo
            if [[ "$p1" == "$p2" && -n "$p1" && ${#p1} -ge 6 ]]; then
                ADMIN_RESET_FINAL_PASS="$p1"; break
            fi
            warn "两次输入不一致或不满 6 位，请重试"
        done
    else
        warn "跳过管理员密码重置"
    fi
else
    warn "非交互环境且未设置 ADMIN_RESET_PASS，跳过重置"
fi

if [[ -n "$ADMIN_RESET_FINAL_PASS" ]]; then
    log "重置管理员密码..."
    HASH=$(python3 -c "import hashlib,sys;print(hashlib.sha256((sys.argv[1]+'987654321hello').encode()).hexdigest()[:32])" "$ADMIN_RESET_FINAL_PASS")
    mysql "$DB_NAME" -e "UPDATE b_user SET password='$HASH' WHERE role=1;" || true
    log "已重置。账号: admin111 / admin"
fi

# ---- 7. systemd 服务 ----
log "写入 systemd unit 文件..."
cat > /etc/systemd/system/b2b-django.service <<EOF
[Unit]
Description=Web B2B Django backend
After=network.target mariadb.service
Requires=mariadb.service

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$TARGET_DIR/server
ExecStart=$TARGET_DIR/server/.venv/bin/python manage.py runserver 0.0.0.0:8000 --noreload
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/b2b-next.service <<EOF
[Unit]
Description=Web B2B Next.js frontend
After=network.target b2b-django.service

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$TARGET_DIR/web
Environment=NODE_ENV=production
Environment=PORT=3000
ExecStart=/usr/bin/npm run start
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ---- 8. nginx ----
log "写入 nginx 配置 (端口 $NGINX_PORT)..."
LISTEN_LINE="listen $NGINX_PORT default_server;\n    listen [::]:$NGINX_PORT default_server;"
if [[ "$ENABLE_HTTPS" == "1" && "$NGINX_PORT" == "80" ]]; then
    # HTTPS 模式下，80 不设为 default_server（留给 443）
    LISTEN_LINE="listen 80;\n    listen [::]:80;"
fi
cat > /etc/nginx/sites-available/b2b <<EOF
server {
    $(printf "$LISTEN_LINE")
    server_name $DOMAIN _;

    client_max_body_size 100M;

    location /upload/ {
        alias $TARGET_DIR/server/upload/;
        access_log off;
        add_header Cache-Control "public, max-age=86400";
    }

    location = /favicon.ico {
        alias $TARGET_DIR/server/upload/img/favicon.ico;
        access_log off;
        log_not_found off;
    }

    location /myapp/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /_next/static {
        proxy_pass http://127.0.0.1:3000;
        access_log off;
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location /_next/image {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        add_header Cache-Control "public, max-age=31536000";
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/b2b /etc/nginx/sites-enabled/b2b
rm -f /etc/nginx/sites-enabled/default
nginx -t

# ---- 8b. Let's Encrypt ----
if [[ "$ENABLE_HTTPS" == "1" ]]; then
    log "安装 certbot 并申请 Let's Encrypt 证书 ($DOMAIN)..."
    apt-get install -y -qq certbot python3-certbot-nginx >/dev/null
    systemctl reload nginx
    # 检查域名是否解析到本机
    PUB_IP=$(curl -fsS --max-time 5 https://api.ipify.org || echo "")
    DOM_IP=$(getent hosts "$DOMAIN" | awk 'NR==1{print $1}')
    if [[ -n "$PUB_IP" && -n "$DOM_IP" && "$PUB_IP" != "$DOM_IP" ]]; then
        warn "域名 $DOMAIN 解析到 $DOM_IP，但本机公网 IP 是 $PUB_IP。certbot 很可能失败。"
    fi
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect -m "$ADMIN_EMAIL" --no-eff-email; then
        log "✅ 证书申请成功，已启用 HTTPS 并重定向 80→43"
    else
        warn "certbot 申请失败。检查：1) 域名 DNS 是否指向本机 2) 80 端口是否可达 3) 防火墙。HTTP 仍可用。"
    fi
fi

# ---- 9. 启动服务 ----
log "启动所有服务..."
systemctl daemon-reload
systemctl enable --now b2b-django b2b-next nginx >/dev/null
systemctl restart b2b-django b2b-next nginx

# ---- 10. 检验 ----
sleep 5
log "检验服务..."
for i in $(seq 1 10); do
    if curl -sf -o /dev/null "http://127.0.0.1:$NGINX_PORT/"; then
        BACKEND_OK=$(curl -sf "http://127.0.0.1:$NGINX_PORT/myapp/index/home/section" | head -c 12)
        log "✅ nginx 起来了，后端响应: $BACKEND_OK"
        break
    fi
    sleep 2
done

if [[ "$ENABLE_HTTPS" == "1" ]] && certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
    URL="https://$DOMAIN/"
else
    URL="http://${DOMAIN}:${NGINX_PORT}/"
    [[ "$NGINX_PORT" == "80" ]] && URL="http://${DOMAIN}/"
fi
ADMIN_TIP="admin111 / 你设置的新密码"
[[ -z "$ADMIN_RESET_FINAL_PASS" ]] && ADMIN_TIP="admin111 / (未重置，使用原密码或数据库中的密码)"

cat <<DONE

✅ 部署完成

访问地址:
  $URL
  后台登录: ${URL}adminLogin ($ADMIN_TIP)

服务管理:
  systemctl status b2b-django b2b-next nginx
  journalctl -u b2b-next -f

DONE
