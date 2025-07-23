#!/bin/bash

echo "=== MySQL 连接权限快速修复脚本 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取用户输入
echo -e "${BLUE}请提供以下信息:${NC}"
read -p "MySQL服务器IP地址 (默认: 10.23.192.206): " MYSQL_HOST
MYSQL_HOST=${MYSQL_HOST:-10.23.192.206}

read -p "MySQL root密码: " -s MYSQL_ROOT_PASSWORD
echo ""

read -p "要创建的应用用户名 (默认: bench_user): " APP_USER
APP_USER=${APP_USER:-bench_user}

read -p "应用用户密码 (默认: bench_password): " APP_PASSWORD
APP_PASSWORD=${APP_PASSWORD:-bench_password}

read -p "应用服务器IP (为了安全，留空表示允许任何IP): " CLIENT_IP

echo ""
echo -e "${BLUE}配置信息:${NC}"
echo "MySQL服务器: $MYSQL_HOST"
echo "应用用户: $APP_USER"
echo "客户端IP: ${CLIENT_IP:-任何IP}"

echo ""
read -p "确认执行? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

echo ""
echo -e "${BLUE}1. 测试MySQL连接...${NC}"

# 测试连接
if mysql -h "$MYSQL_HOST" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ MySQL连接成功${NC}"
else
    echo -e "${RED}❌ MySQL连接失败，请检查:${NC}"
    echo "- MySQL服务器地址: $MYSQL_HOST"
    echo "- root密码是否正确"
    echo "- 网络连接是否正常"
    echo "- MySQL服务是否运行"
    exit 1
fi

echo ""
echo -e "${BLUE}2. 创建数据库和用户...${NC}"

# 确定主机范围
if [ -z "$CLIENT_IP" ]; then
    HOST_PATTERN="%"
    echo "允许从任何IP连接"
else
    HOST_PATTERN="$CLIENT_IP"
    echo "只允许从 $CLIENT_IP 连接"
fi

# 创建SQL命令
SQL_COMMANDS="
-- 创建数据库
CREATE DATABASE IF NOT EXISTS bench_server CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建用户
CREATE USER IF NOT EXISTS '${APP_USER}'@'${HOST_PATTERN}' IDENTIFIED BY '${APP_PASSWORD}';

-- 授权
GRANT ALL PRIVILEGES ON bench_server.* TO '${APP_USER}'@'${HOST_PATTERN}';
FLUSH PRIVILEGES;

-- 显示结果
SELECT 'Database created' as Status;
SELECT User, Host FROM mysql.user WHERE User = '${APP_USER}';
"

# 执行SQL命令
echo "$SQL_COMMANDS" | mysql -h "$MYSQL_HOST" -u root -p"$MYSQL_ROOT_PASSWORD"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 用户和数据库创建成功${NC}"
else
    echo -e "${RED}❌ 创建失败${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}3. 初始化数据库表...${NC}"

if [ -f "init.sql" ]; then
    mysql -h "$MYSQL_HOST" -u "$APP_USER" -p"$APP_PASSWORD" bench_server < init.sql
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 数据库表初始化成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 数据库表初始化失败，但用户已创建${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ 未找到 init.sql 文件，跳过表初始化${NC}"
fi

echo ""
echo -e "${BLUE}4. 测试应用用户连接...${NC}"

if mysql -h "$MYSQL_HOST" -u "$APP_USER" -p"$APP_PASSWORD" -e "USE bench_server; SHOW TABLES;" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 应用用户连接测试成功${NC}"
else
    echo -e "${RED}❌ 应用用户连接测试失败${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== 修复完成! ===${NC}"
echo ""
echo -e "${YELLOW}配置信息:${NC}"

echo ""
echo "修改你的 config.yaml:"
cat << EOF
database:
  host: "$MYSQL_HOST"
  port: "3306"
  user: "$APP_USER"
  password: "$APP_PASSWORD"
  name: "bench_server"
  max_open_conns: 25
  max_idle_conns: 5
EOF

echo ""
echo "或者使用环境变量:"
echo "export DB_HOST=\"$MYSQL_HOST\""
echo "export DB_PORT=\"3306\""
echo "export DB_USER=\"$APP_USER\""
echo "export DB_PASSWORD=\"$APP_PASSWORD\""
echo "export DB_NAME=\"bench_server\""

echo ""
echo -e "${BLUE}现在可以启动应用:${NC}"
echo "./bench-server" 