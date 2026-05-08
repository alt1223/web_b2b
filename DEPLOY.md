# Web B2B 一键部署指南

两种部署方式，任选一种。

---

## 方式 A：Shell 一键脚本（Ubuntu / Debian）

### 适用场景
全新的 Ubuntu 22.04+ / Debian 12+ 服务器，拥有 sudo。

### 使用

```bash
git clone <本项目地址> web_b2b
cd web_b2b
sudo bash deploy.sh                      # 默认 localhost
sudo bash deploy.sh shop.example.com     # 指定域名
```

### 可选环境变量

```bash
sudo DB_PASS=你的密码 ADMIN_RESET_PASS=newadmin NGINX_PORT=80 bash deploy.sh shop.example.com
```

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DB_NAME` | `python_db` | 数据库名 |
| `DB_USER` | `b2b` | 数据库用户 |
| `DB_PASS` | `b2bpass` | 数据库密码 |
| `NGINX_PORT` | `8080` | nginx 监听端口 |
| `ADMIN_RESET_PASS` | `admin123` | 重置后台管理员密码（admin111 / admin）为此值 |

### 完成后访问

- 首页：`http://服务器IP:8080/`
- 后台：`http://服务器IP:8080/adminLogin` （`admin111` / `admin123`）

### 服务管理

```bash
systemctl status b2b-django b2b-next nginx
systemctl restart b2b-next         # 重启前端
systemctl restart b2b-django       # 重启后端
journalctl -u b2b-next -f          # 看前端日志
```

### 代码修改后

```bash
cd /项目路径/web && npm run build && sudo systemctl restart b2b-next
sudo systemctl restart b2b-django
```

---

## 方式 B：Docker Compose（跨平台）

### 适用场景
任何平台（Linux / macOS / Windows），只要装了 Docker + Docker Compose。

### 使用

```bash
git clone <本项目地址> web_b2b
cd web_b2b
docker compose up -d --build
```

首次启动会自动创建数据库并导入 `web_b2b.sql` 初始数据。

### 访问

- 首页：http://localhost:8080/
- 后台：http://localhost:8080/adminLogin
  - 默认账号密码是 SQL 里的（参考 README）。如需重置为 `admin123`：
    ```bash
    docker compose exec db sh -c "echo \"UPDATE python_db.b_user SET password='9be0ded4b62c84780c2882a60a6191c7' WHERE role=1;\" | mysql -ub2b -pb2bpass python_db"
    ```

### 可选环境变量

在 `docker-compose up` 前设置：

```bash
DOMAIN=shop.example.com HOST_PORT=80 docker compose up -d --build
```

### 货柜管理

```bash
docker compose ps
docker compose logs -f next        # 看前端日志
docker compose restart next        # 重启前端
docker compose down                # 停掉（保留数据）
docker compose down -v             # 停掉并删除数据卷
```

---

## 绑定自定义域名 (两种部署方式都适用)

### 场景 1：VPS 有独立公网 IP

1. 把域名 A 记录指向 IP
2. 把 NGINX_PORT 改为 80，重跑部署脚本；Docker 模式则 `HOST_PORT=80`
3. 可选：装 certbot 拿 Let's Encrypt 免费证书

### 场景 2：exe.dev / 不能绑 80 端口的平台

用 Cloudflare Worker 中转：

1. 部署一个 Cloudflare Worker，代码如下：
   ```js
   const ORIGIN = 'https://你的主机:8080';
   export default {
     async fetch(request) {
       const url = new URL(request.url);
       const headers = new Headers(request.headers);
       headers.set('host', new URL(ORIGIN).host);
       return fetch(ORIGIN + url.pathname + url.search, {
         method: request.method,
         headers,
         body: ['GET','HEAD'].includes(request.method) ? undefined : request.body,
         redirect: 'manual',
       });
     }
   };
   ```
2. Worker 设置 → 域和路由 → 添加自定义域 →填你的域名
3. SSL/TLS 模式选 “完整 Full”

---

## 项目结构

```
web_b2b/
├─ server/                Django 后端
├─ web/                   Next.js 前端
├─ web_b2b.sql            初始化 SQL
├─ deploy.sh              一键部署脚本（方式 A）
├─ docker-compose.yml     Docker 部署（方式 B）
└─ docker/
   ├─ Dockerfile.django
   ├─ Dockerfile.next
   └─ nginx.conf
```

## 常见问题

**Q: 后台登录报“用户名或密码错误”**
A: 默认密码是 `admin123`，账号是 `admin111` 或 `admin`（README 上写的 admin123 是错的）。脚本会自动重置。

**Q: logo、产品图片 403**
A: 脚本已加上了目录权限修正。手动修复：`sudo chmod o+x /home /home/$USER /home/$USER/web_b2b ...`

**Q: 修改代码后看不到变化**
A: 前端需要 `npm run build` + 重启服务。Docker 模式 `docker compose up -d --build next`。
