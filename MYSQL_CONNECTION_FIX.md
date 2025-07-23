# MySQL 连接权限问题解决指南

## 问题描述
错误信息: `Host '10.23.192.206' is not allowed to connect to this MySQL server`

这个错误表示MySQL服务器配置不允许来自IP地址 `10.23.192.206` 的连接。

## 解决方案

### 方案1: 快速修复 (推荐用于开发环境)

在MySQL服务器上执行以下命令：

```bash
# 连接到MySQL (需要在MySQL服务器上执行)
mysql -u root -p

# 在MySQL中执行
CREATE USER IF NOT EXISTS 'bench_user'@'%' IDENTIFIED BY 'bench_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_user'@'%';
FLUSH PRIVILEGES;
```

然后修改你的配置文件：

```yaml
database:
  host: "10.23.192.206"  # MySQL服务器IP
  port: "3306"
  user: "bench_user"
  password: "bench_password"
  name: "bench_server"
```

### 方案2: 使用环境变量

```bash
export DB_HOST="10.23.192.206"
export DB_USER="bench_user"
export DB_PASSWORD="bench_password"
./bench-server
```

### 方案3: 为特定IP创建用户 (更安全)

```sql
-- 只允许从特定IP连接
CREATE USER IF NOT EXISTS 'bench_user'@'10.23.192.206' IDENTIFIED BY 'bench_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_user'@'10.23.192.206';
FLUSH PRIVILEGES;
```

### 方案4: 修改现有root用户权限

⚠️ **警告**: 不推荐在生产环境中使用

```sql
-- 允许root从任何地方连接 (仅开发环境)
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

## 自动修复脚本

运行以下命令自动修复权限：

```bash
# 在MySQL服务器上执行
mysql -u root -p < fix_mysql_connection.sql
```

## 检查和验证

### 1. 检查MySQL用户和主机权限

```sql
SELECT User, Host FROM mysql.user;
SHOW GRANTS FOR 'bench_user'@'%';
```

### 2. 测试连接

```bash
# 从应用服务器测试连接
mysql -h 10.23.192.206 -u bench_user -p bench_server
```

### 3. 验证应用连接

```bash
# 设置环境变量并测试
export DB_HOST="10.23.192.206"
export DB_USER="bench_user"
export DB_PASSWORD="bench_password"
./bench-server
```

## MySQL服务器配置检查

### 1. 检查bind-address设置

编辑MySQL配置文件 (`/etc/mysql/mysql.conf.d/mysqld.cnf` 或 `/etc/my.cnf`):

```ini
[mysqld]
# 允许外部连接 (注释掉或修改以下行)
# bind-address = 127.0.0.1
bind-address = 0.0.0.0
```

### 2. 重启MySQL服务

```bash
sudo systemctl restart mysql
# 或
sudo service mysql restart
```

### 3. 检查防火墙

```bash
# Ubuntu/Debian
sudo ufw allow 3306

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=3306/tcp
sudo firewall-cmd --reload
```

## 生产环境安全建议

### 1. 创建专用数据库用户

```sql
CREATE USER 'bench_app'@'10.23.192.206' IDENTIFIED BY 'strong_password_here';
GRANT SELECT, INSERT, UPDATE, DELETE ON bench_server.* TO 'bench_app'@'10.23.192.206';
FLUSH PRIVILEGES;
```

### 2. 使用SSL连接

在配置中启用SSL:

```yaml
database:
  host: "10.23.192.206"
  port: "3306"
  user: "bench_app"
  password: "strong_password_here"
  name: "bench_server"
  ssl_mode: "require"  # 如果支持
```

### 3. 限制IP范围

```sql
-- 只允许特定网段
CREATE USER 'bench_app'@'10.23.192.%' IDENTIFIED BY 'strong_password_here';
```

## 常见错误排查

### 1. 连接超时
- 检查网络连通性: `ping 10.23.192.206`
- 检查端口: `telnet 10.23.192.206 3306`

### 2. 密码认证失败
- 确认密码正确
- 检查用户是否存在: `SELECT User, Host FROM mysql.user;`

### 3. 数据库不存在
- 创建数据库: `CREATE DATABASE bench_server;`
- 或运行初始化脚本: `mysql -u root -p < init.sql`

## 完整示例

假设你有两台服务器：
- MySQL服务器: 10.23.192.206
- 应用服务器: 10.23.192.100

在MySQL服务器上执行：

```sql
-- 创建用户和数据库
CREATE DATABASE IF NOT EXISTS bench_server;
CREATE USER IF NOT EXISTS 'bench_app'@'10.23.192.100' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_app'@'10.23.192.100';
FLUSH PRIVILEGES;
```

在应用服务器上修改配置：

```yaml
database:
  host: "10.23.192.206"
  port: "3306"
  user: "bench_app"
  password: "secure_password"
  name: "bench_server"
```

这样就可以安全地连接到远程MySQL服务器了。 