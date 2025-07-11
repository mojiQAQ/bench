-- SQL 迁移脚本: 添加 data 字段到传感器数据表
-- 用于增大数据传输量进行压测

-- 检查并添加 data 字段到 time_series_data 表
ALTER TABLE time_series_data 
ADD COLUMN IF NOT EXISTS data TEXT COMMENT '随机负载数据，用于增大传输量';

-- 检查并添加 data 字段到 time_series_partitioned 表
ALTER TABLE time_series_partitioned 
ADD COLUMN IF NOT EXISTS data TEXT COMMENT '随机负载数据，用于增大传输量';

-- 创建索引以提高查询性能（可选）
-- CREATE INDEX idx_data_size ON time_series_data ((LENGTH(data)));

-- 验证字段是否添加成功
DESCRIBE time_series_data;
DESCRIBE time_series_partitioned;

-- 显示表结构信息
SHOW CREATE TABLE time_series_data;
SHOW CREATE TABLE time_series_partitioned;

-- 测试插入带有data字段的数据
INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data) 
VALUES (
    NOW(), 
    'test_device_migration', 
    'temperature', 
    25.5, 
    2, 
    'eyJ0ZXN0IjoidGVzdF9kYXRhIiwic2l6ZSI6MTAyNCwidGltZXN0YW1wIjoiMjAyNC0wMS0wMVQxMDowMDowMFoifQ=='
);

-- 验证插入的数据
SELECT 
    id,
    timestamp,
    device_id,
    metric_name,
    value,
    priority,
    SUBSTRING(data, 1, 50) as data_preview,
    LENGTH(data) as data_length,
    created_at
FROM time_series_data 
WHERE device_id = 'test_device_migration'
ORDER BY created_at DESC 
LIMIT 1;

-- 清理测试数据
DELETE FROM time_series_data WHERE device_id = 'test_device_migration';

-- 显示迁移完成信息
SELECT 'Data field migration completed successfully!' as status; 