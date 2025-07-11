#!/bin/bash

# 测试传感器数据查询接口
# 作者: AI Assistant
# 日期: 2024-01-01

set -e

SERVER_URL="http://localhost:8080"
API_ENDPOINT="/api/get-sensor-data"

echo "=========================================="
echo "传感器数据查询接口测试"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试函数
test_api() {
    local test_name="$1"
    local request_data="$2"
    local expected_status="$3"
    
    echo -e "${BLUE}测试: $test_name${NC}"
    echo "请求数据: $request_data"
    
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        "$SERVER_URL$API_ENDPOINT")
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ 状态码正确: $http_code${NC}"
        if [ "$http_code" = "200" ]; then
            echo "响应数据:"
            echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        fi
    else
        echo -e "${RED}✗ 状态码错误: 期望 $expected_status, 实际 $http_code${NC}"
        echo "响应内容: $response_body"
        return 1
    fi
    echo ""
}

# 检查服务器是否运行
echo -e "${YELLOW}检查服务器状态...${NC}"
if ! curl -s "$SERVER_URL/health" > /dev/null; then
    echo -e "${RED}错误: 服务器未运行在 $SERVER_URL${NC}"
    echo "请先启动服务器: go run ."
    exit 1
fi
echo -e "${GREEN}✓ 服务器运行正常${NC}"
echo ""

# 测试1: 查询设备所有指标（正常情况）
test_api "查询设备所有指标" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 10,
    "offset": 0
}' "200"

# 测试2: 查询特定指标
test_api "查询特定指标" '{
    "device_id": "factory_001_device_001",
    "metric_name": "temperature",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 5
}' "200"

# 测试3: 分页查询
test_api "分页查询" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 2,
    "offset": 1
}' "200"

# 测试4: 缺少必需字段
test_api "缺少必需字段" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z"
}' "400"

# 测试5: 无效时间格式
test_api "无效时间格式" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01",
    "end_time": "2024-12-31T23:59:59Z"
}' "400"

# 测试6: 时间范围错误
test_api "时间范围错误" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-12-31T23:59:59Z",
    "end_time": "2024-01-01T00:00:00Z"
}' "400"

# 测试7: 不存在的设备
test_api "不存在的设备" '{
    "device_id": "nonexistent_device",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z"
}' "200"

# 测试8: 大量数据查询（测试限制）
test_api "大量数据查询" '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 15000
}' "200"

# 测试9: 错误的HTTP方法
echo -e "${BLUE}测试: 错误的HTTP方法${NC}"
response=$(curl -s -w "\n%{http_code}" -X GET "$SERVER_URL$API_ENDPOINT")
http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "405" ]; then
    echo -e "${GREEN}✓ 正确拒绝GET请求${NC}"
else
    echo -e "${RED}✗ 应该拒绝GET请求，但返回了 $http_code${NC}"
fi
echo ""

# 测试10: 无效JSON
echo -e "${BLUE}测试: 无效JSON${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"invalid": json}' \
    "$SERVER_URL$API_ENDPOINT")
http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "400" ]; then
    echo -e "${GREEN}✓ 正确拒绝无效JSON${NC}"
else
    echo -e "${RED}✗ 应该拒绝无效JSON，但返回了 $http_code${NC}"
fi
echo ""

echo "=========================================="
echo -e "${GREEN}所有测试完成！${NC}"
echo "=========================================="

# 性能测试（可选）
echo -e "${YELLOW}是否进行性能测试？(y/N)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}开始性能测试...${NC}"
    
    # 并发查询测试
    echo "并发查询测试（10个并发请求）:"
    for i in {1..10}; do
        (curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{
                "device_id": "factory_001_device_001",
                "start_time": "2024-01-01T00:00:00Z",
                "end_time": "2024-12-31T23:59:59Z",
                "limit": 100
            }' \
            "$SERVER_URL$API_ENDPOINT" > /dev/null) &
    done
    
    wait
    echo -e "${GREEN}✓ 并发查询测试完成${NC}"
    
    # 响应时间测试
    echo "响应时间测试:"
    start_time=$(date +%s%3N)
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{
            "device_id": "factory_001_device_001",
            "start_time": "2024-01-01T00:00:00Z",
            "end_time": "2024-12-31T23:59:59Z",
            "limit": 1000
        }' \
        "$SERVER_URL$API_ENDPOINT" > /dev/null
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    echo "查询1000条记录耗时: ${duration}ms"
    
    if [ $duration -lt 1000 ]; then
        echo -e "${GREEN}✓ 响应时间良好 (<1s)${NC}"
    else
        echo -e "${YELLOW}⚠ 响应时间较慢 (>1s)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}测试脚本执行完成！${NC}" 