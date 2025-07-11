#!/bin/bash

# 性能测试脚本
# 使用方法: ./benchmark.sh [test_type] [duration] [concurrency]

set -e

# 默认参数
TEST_TYPE=${1:-"sensor"}
DURATION=${2:-"60s"}
CONCURRENCY=${3:-"100"}

SERVER_URL="http://localhost:8080"
LOG_DIR="benchmark_logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 创建日志目录
mkdir -p $LOG_DIR

echo "=== Bench Server 性能测试 ==="
echo "测试类型: $TEST_TYPE"
echo "持续时间: $DURATION"
echo "并发数: $CONCURRENCY"
echo "时间戳: $TIMESTAMP"
echo "================================"

# 检查服务器是否运行
echo "检查服务器状态..."
if ! curl -s "$SERVER_URL/health" > /dev/null; then
    echo "错误: 服务器未运行或无法访问"
    exit 1
fi
echo "服务器运行正常"

# 根据测试类型选择不同的测试
case $TEST_TYPE in
    "sensor")
        echo "开始传感器数据压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/sensor-data > $LOG_DIR/sensor_${TIMESTAMP}.log
        ;;
    "sensor-rw")
        echo "开始传感器读写操作压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/sensor-rw > $LOG_DIR/sensor_rw_${TIMESTAMP}.log
        ;;
    "batch-sensor-rw")
        echo "开始批量传感器读写操作压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/batch-sensor-rw > $LOG_DIR/batch_sensor_rw_${TIMESTAMP}.log
        ;;
    "all")
        echo "开始全面压测..."
        
        echo "1. 传感器数据压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/sensor-data > $LOG_DIR/sensor_${TIMESTAMP}.log
        
        echo "2. 传感器读写操作压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/sensor-rw > $LOG_DIR/sensor_rw_${TIMESTAMP}.log
        
        echo "3. 批量传感器读写操作压测..."
        wrk -t12 -c$CONCURRENCY -d$DURATION -s test_data.lua $SERVER_URL/api/batch-sensor-rw > $LOG_DIR/batch_sensor_rw_${TIMESTAMP}.log
        ;;
    *)
        echo "未知的测试类型: $TEST_TYPE"
        echo "支持的测试类型: sensor, sensor-rw, batch-sensor-rw, all"
        exit 1
        ;;
esac

echo "测试完成！"
echo "日志文件保存在: $LOG_DIR/"

# 显示测试结果摘要
if [ "$TEST_TYPE" = "all" ]; then
    echo ""
    echo "=== 测试结果摘要 ==="
    for log_file in $LOG_DIR/*_${TIMESTAMP}.log; do
        if [ -f "$log_file" ]; then
            echo ""
            echo "文件: $(basename $log_file)"
            echo "----------------------------------------"
            grep -E "(Requests/sec|Latency|Socket errors|Non-2xx or 3xx responses)" "$log_file" || echo "未找到关键指标"
        fi
    done
else
    log_file="$LOG_DIR/${TEST_TYPE}_${TIMESTAMP}.log"
    if [ -f "$log_file" ]; then
        echo ""
        echo "=== 测试结果摘要 ==="
        echo "文件: $(basename $log_file)"
        echo "----------------------------------------"
        grep -E "(Requests/sec|Latency|Socket errors|Non-2xx or 3xx responses)" "$log_file" || echo "未找到关键指标"
    fi
fi

# 获取系统统计信息
echo ""
echo "=== 系统统计信息 ==="
curl -s "$SERVER_URL/api/stats" | jq . 2>/dev/null || echo "无法获取统计信息"

echo ""
echo "测试完成！详细结果请查看日志文件。" 