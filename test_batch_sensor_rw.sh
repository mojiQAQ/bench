#!/bin/bash

# 批量传感器读写功能测试脚本

SERVER_URL="http://localhost:8080"

echo "=== 批量传感器读写功能测试 ==="

# 检查服务器状态
echo "1. 检查服务器状态..."
if ! curl -s "$SERVER_URL/health" > /dev/null; then
    echo "错误: 服务器未运行"
    exit 1
fi
echo "✓ 服务器运行正常"

# 测试1: 批量传感器读写操作 - 正常值
echo ""
echo "2. 测试批量传感器读写操作 - 正常值..."
response=$(curl -s -X POST "$SERVER_URL/api/batch-sensor-rw" \
  -H "Content-Type: application/json" \
  -d '{
    "data": [
      {
        "device_id": "test_device_001",
        "metric_name": "temperature",
        "new_value": 25.5,
        "timestamp": "2024-01-01T10:00:00Z",
        "priority": 2
      },
      {
        "device_id": "test_device_002",
        "metric_name": "pressure",
        "new_value": 101.3,
        "timestamp": "2024-01-01T10:00:01Z",
        "priority": 2
      },
      {
        "device_id": "test_device_003",
        "metric_name": "humidity",
        "new_value": 60.2,
        "timestamp": "2024-01-01T10:00:02Z",
        "priority": 3
      }
    ]
  }')

echo "响应: $response"

# 测试2: 批量传感器读写操作 - 包含告警值
echo ""
echo "3. 测试批量传感器读写操作 - 包含告警值..."
response=$(curl -s -X POST "$SERVER_URL/api/batch-sensor-rw" \
  -H "Content-Type: application/json" \
  -d '{
    "data": [
      {
        "device_id": "test_device_001",
        "metric_name": "temperature",
        "new_value": 105.5,
        "timestamp": "2024-01-01T10:01:00Z",
        "priority": 2
      },
      {
        "device_id": "test_device_002",
        "metric_name": "pressure",
        "new_value": 120.8,
        "timestamp": "2024-01-01T10:01:01Z",
        "priority": 2
      },
      {
        "device_id": "test_device_003",
        "metric_name": "voltage",
        "new_value": 85.2,
        "timestamp": "2024-01-01T10:01:02Z",
        "priority": 1
      }
    ]
  }')

echo "响应: $response"

# 测试3: 查看统计信息
echo ""
echo "4. 查看统计信息..."
response=$(curl -s "$SERVER_URL/api/stats")
echo "响应: $response"

echo ""
echo "=== 测试完成 ===" 