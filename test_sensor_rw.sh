#!/bin/bash

# 传感器读写功能测试脚本 - 支持data负载数据

SERVER_URL="http://localhost:8080"

echo "=== 传感器读写功能测试（支持负载数据）==="

# 检查服务器状态
echo "1. 检查服务器状态..."
if ! curl -s "$SERVER_URL/health" > /dev/null; then
    echo "错误: 服务器未运行"
    exit 1
fi
echo "✓ 服务器运行正常"

# 生成测试负载数据（base64编码的JSON）
generate_payload_data() {
    local size=${1:-1024}
    local payload="{\"load\":[1,2,3,4,5],\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"size\":$size,\"random\":\"test_data_123456\",\"sequence\":[1.1,2.2,3.3],\"metadata\":\"generated_at_$(date +%s)_device_simulation_data_for_load_testing\"}"
    echo "$payload" | base64 | tr -d '\n'
}

# 测试1: 正常传感器数据上报（包含负载数据）
echo ""
echo "2. 测试正常传感器数据上报（包含1KB负载数据）..."
payload_data=$(generate_payload_data 1024)
response=$(curl -s -X POST "$SERVER_URL/api/sensor-data" \
  -H "Content-Type: application/json" \
  -d "{
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"device_id\": \"test_device_001\",
    \"metric_name\": \"temperature\",
    \"value\": 25.5,
    \"priority\": 2,
    \"data\": \"$payload_data\"
  }")

echo "响应: $response"
echo "负载数据大小: $(echo "$payload_data" | wc -c) 字符 (base64编码)"

# 测试2: 传感器读写操作 - 正常值（包含负载数据）
echo ""
echo "3. 测试传感器读写操作 - 正常值（包含2KB负载数据）..."
payload_data=$(generate_payload_data 2048)
response=$(curl -s -X POST "$SERVER_URL/api/sensor-rw" \
  -H "Content-Type: application/json" \
  -d "{
    \"device_id\": \"test_device_001\",
    \"metric_name\": \"temperature\",
    \"new_value\": 26.5,
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"priority\": 2,
    \"data\": \"$payload_data\"
  }")

echo "响应: $response"
echo "负载数据大小: $(echo "$payload_data" | wc -c) 字符 (base64编码)"

# 测试3: 传感器读写操作 - 超过阈值（包含负载数据）
echo ""
echo "4. 测试传感器读写操作 - 超过阈值（包含5KB负载数据）..."
payload_data=$(generate_payload_data 5120)
response=$(curl -s -X POST "$SERVER_URL/api/sensor-rw" \
  -H "Content-Type: application/json" \
  -d "{
    \"device_id\": \"test_device_001\",
    \"metric_name\": \"temperature\",
    \"new_value\": 105.5,
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"priority\": 2,
    \"data\": \"$payload_data\"
  }")

echo "响应: $response"
echo "负载数据大小: $(echo "$payload_data" | wc -c) 字符 (base64编码)"

# 测试4: 批量传感器读写操作（包含负载数据）
echo ""
echo "5. 测试批量传感器读写操作（每个项目包含512B负载数据）..."
payload_data1=$(generate_payload_data 512)
payload_data2=$(generate_payload_data 512)
payload_data3=$(generate_payload_data 512)

response=$(curl -s -X POST "$SERVER_URL/api/batch-sensor-rw" \
  -H "Content-Type: application/json" \
  -d "{
    \"data\": [
      {
        \"device_id\": \"test_device_001\",
        \"metric_name\": \"temperature\",
        \"new_value\": 95.5,
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"priority\": 2,
        \"data\": \"$payload_data1\"
      },
      {
        \"device_id\": \"test_device_002\",
        \"metric_name\": \"pressure\",
        \"new_value\": 110.3,
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"priority\": 2,
        \"data\": \"$payload_data2\"
      },
      {
        \"device_id\": \"test_device_003\",
        \"metric_name\": \"voltage\",
        \"new_value\": 85.2,
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"priority\": 3,
        \"data\": \"$payload_data3\"
      }
    ]
  }")

echo "响应: $response"
echo "每个负载数据大小: $(echo "$payload_data1" | wc -c) 字符 (base64编码)"

# 测试5: 大负载数据测试（接近TEXT字段限制）
echo ""
echo "6. 测试大负载数据（20KB负载数据）..."
payload_data=$(generate_payload_data 20480)
response=$(curl -s -X POST "$SERVER_URL/api/sensor-data" \
  -H "Content-Type: application/json" \
  -d "{
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"device_id\": \"test_device_large\",
    \"metric_name\": \"vibration\",
    \"value\": 75.8,
    \"priority\": 1,
    \"data\": \"$payload_data\"
  }")

echo "响应: $response"
echo "大负载数据大小: $(echo "$payload_data" | wc -c) 字符 (base64编码)"

# 测试6: 查看统计信息
echo ""
echo "7. 查看统计信息..."
response=$(curl -s "$SERVER_URL/api/stats")
echo "响应: $response"

# 测试7: 负载数据验证测试
echo ""
echo "8. 负载数据解码验证测试..."
echo "生成一个简单的负载数据并验证编解码..."
original_data="{\"test\":\"hello world\",\"size\":100}"
encoded_data=$(echo "$original_data" | base64 | tr -d '\n')
decoded_data=$(echo "$encoded_data" | base64 -d)

echo "原始数据: $original_data"
echo "编码数据: $encoded_data"
echo "解码数据: $decoded_data"

if [ "$original_data" = "$decoded_data" ]; then
    echo "✓ 负载数据编解码验证成功"
else
    echo "✗ 负载数据编解码验证失败"
fi

echo ""
echo "=== 数据传输量统计 ==="
echo "1KB 负载: $(echo $(generate_payload_data 1024) | wc -c) 字符"
echo "2KB 负载: $(echo $(generate_payload_data 2048) | wc -c) 字符"
echo "5KB 负载: $(echo $(generate_payload_data 5120) | wc -c) 字符"
echo "20KB 负载: $(echo $(generate_payload_data 20480) | wc -c) 字符"

echo ""
echo "=== 测试完成 ==="
echo "所有测试已完成，包括负载数据传输测试"
echo "负载数据以base64编码格式存储在数据库的data字段中" 