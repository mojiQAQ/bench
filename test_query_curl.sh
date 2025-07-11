#!/bin/bash

# 简单的curl测试脚本 - 验证查询接口
# 用于快速验证/api/get-sensor-data接口功能

SERVER_URL="http://localhost:8080"
API_ENDPOINT="/api/get-sensor-data"

echo "========================================"
echo "传感器数据查询接口 - 快速验证"
echo "========================================"

# 检查服务器状态
echo "1. 检查服务器状态..."
curl -s "$SERVER_URL/health" | jq '.' 2>/dev/null || echo "服务器可能未运行"
echo ""

# 测试1: 查询设备所有指标
echo "2. 查询设备所有指标..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 5
  }' \
  "$SERVER_URL$API_ENDPOINT" | jq '.' 2>/dev/null || echo "查询失败"
echo ""

# 测试2: 查询特定指标
echo "3. 查询特定指标 (temperature)..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "metric_name": "temperature",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 3
  }' \
  "$SERVER_URL$API_ENDPOINT" | jq '.' 2>/dev/null || echo "查询失败"
echo ""

# 测试3: 分页查询
echo "4. 分页查询 (offset=1, limit=2)..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 2,
    "offset": 1
  }' \
  "$SERVER_URL$API_ENDPOINT" | jq '.' 2>/dev/null || echo "查询失败"
echo ""

# 测试4: 时间范围查询
echo "5. 时间范围查询 (最近一天)..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "'$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)'",
    "end_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "limit": 10
  }' \
  "$SERVER_URL$API_ENDPOINT" | jq '.' 2>/dev/null || echo "查询失败"
echo ""

# 测试5: 错误测试 - 缺少必需字段
echo "6. 错误测试 - 缺少必需字段..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z"
  }' \
  "$SERVER_URL$API_ENDPOINT" || echo "正确返回错误"
echo ""

# 测试6: 错误测试 - 无效时间格式
echo "7. 错误测试 - 无效时间格式..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01",
    "end_time": "2024-12-31T23:59:59Z"
  }' \
  "$SERVER_URL$API_ENDPOINT" || echo "正确返回错误"
echo ""

echo "========================================"
echo "测试完成！"
echo "========================================" 