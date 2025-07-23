-- MySQL 连接权限修复脚本
-- 需要以 MySQL root 用户身份执行

-- 选项1: 允许 root 用户从指定 IP 连接
CREATE USER IF NOT EXISTS 'root'@'10.23.192.206' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'10.23.192.206' WITH GRANT OPTION;

-- 选项2: 允许 root 用户从任何 IP 连接 (不推荐用于生产环境)
-- CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
-- GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- 选项3: 创建专用的应用用户
CREATE USER IF NOT EXISTS 'bench_user'@'10.23.192.206' IDENTIFIED BY 'bench_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_user'@'10.23.192.206';

-- 选项4: 创建可以从任何地方连接的应用用户
CREATE USER IF NOT EXISTS 'bench_user'@'%' IDENTIFIED BY 'bench_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_user'@'%';

-- 刷新权限
FLUSH PRIVILEGES;

-- 查看用户权限
SELECT User, Host FROM mysql.user WHERE User IN ('root', 'bench_user');

-- 显示当前用户权限
SHOW GRANTS FOR 'root'@'localhost';
SHOW GRANTS FOR 'bench_user'@'%'; 