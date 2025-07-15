-- 创建数据库
CREATE DATABASE IF NOT EXISTS bench_server CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE bench_server;

DROP TABLE IF EXISTS time_series_data;
DROP TABLE IF EXISTS device_status;

-- 创建时序数据表
CREATE TABLE IF NOT EXISTS time_series_data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME(3) NOT NULL,
    device_id VARCHAR(100) NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    value DOUBLE NOT NULL,
    priority TINYINT NOT NULL DEFAULT 2,
    data TEXT COMMENT '随机负载数据，用于增大传输量',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_timestamp (timestamp),
    INDEX idx_device_metric (device_id, metric_name),
    INDEX idx_priority (priority)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 创建设备状态表（用于传感器读写操作）
CREATE TABLE IF NOT EXISTS device_status (
    device_id VARCHAR(100) PRIMARY KEY,
    current_value FLOAT DEFAULT NULL,
    last_update DATETIME(3) NOT NULL,
    alert_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_last_update (last_update),
    INDEX idx_alert_count (alert_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 插入一些传感器测试数据（包含负载数据）
INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data) VALUES 
(NOW(), 'factory_001_device_001', 'temperature', 25.5, 2, 'eyJ0ZXN0IjoidGVzdF9kYXRhIiwic2l6ZSI6MTAyNCwidGltZXN0YW1wIjoiMjAyNC0wMS0wMVQxMDowMDowMFoifQ=='),
(NOW(), 'factory_001_device_002', 'pressure', 101.3, 2, 'eyJsb2FkIjpbMSwyLDMsNF0sInRpbWVzdGFtcCI6IjIwMjQtMDEtMDFUMTA6MDA6MDBaIiwic2l6ZSI6NTEyLCJyYW5kb20iOiJhYmNkZWZnaGlqayJ9'),
(NOW(), 'factory_001_device_003', 'voltage', 110.8, 1, 'eyJzZXF1ZW5jZSI6WzEuMSwyLjIsM10sInNpemUiOjIwNDgsIm1ldGFkYXRhIjoidGVzdF9kYXRhX2Zvcl9sb2FkX3Rlc3RpbmcifQ==')
ON DUPLICATE KEY UPDATE value = VALUES(value);

-- 插入设备状态测试数据
INSERT INTO device_status (device_id, current_value, last_update, alert_count) VALUES 
('factory_001_device_001', 25.5, NOW(), 0),
('factory_001_device_002', 101.3, NOW(), 0),
('factory_001_device_003', 110.8, NOW(), 1)
ON DUPLICATE KEY UPDATE 
    current_value = VALUES(current_value),
    last_update = VALUES(last_update),
    alert_count = VALUES(alert_count);

-- 创建用户并授权
CREATE USER IF NOT EXISTS 'bench_user'@'%' IDENTIFIED BY 'bench_password';
GRANT ALL PRIVILEGES ON bench_server.* TO 'bench_user'@'%';
FLUSH PRIVILEGES;

-- 显示创建的表结构
SHOW CREATE TABLE time_series_data;
SHOW CREATE TABLE device_status;

-- 显示初始化完成信息
SELECT 'Database initialization completed with data field support!' as status; 