#!/bin/bash

# =============================================================================
# Bench Server 负载测试执行脚本
# 基于OpenAPI规范的全面压测套件
# =============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SERVER_URL="http://localhost:8080"
RESULTS_DIR="./load_test_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 创建结果目录
mkdir -p "$RESULTS_DIR"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查服务器状态
check_server() {
    log_info "检查服务器状态..."
    if curl -s "$SERVER_URL/health" > /dev/null; then
        log_success "服务器运行正常"
        return 0
    else
        log_error "服务器不可访问，请确保服务器在 $SERVER_URL 运行"
        return 1
    fi
}

# 检查工具是否安装
check_tool() {
    local tool=$1
    if command -v "$tool" &> /dev/null; then
        log_success "$tool 已安装"
        return 0
    else
        log_warning "$tool 未安装"
        return 1
    fi
}

# 运行wrk压测
run_wrk_test() {
    if ! check_tool wrk; then
        log_warning "跳过wrk测试"
        return
    fi
    
    log_info "运行wrk压测..."
    
    # 健康检查压测
    log_info "执行健康检查压测..."
    wrk -t12 -c50 -d30s --timeout 30s \
        "$SERVER_URL/health" \
        > "$RESULTS_DIR/wrk_health_${TIMESTAMP}.txt"
    
    # 传感器数据上报压测
    log_info "执行传感器数据上报压测..."
    wrk -t12 -c100 -d60s --timeout 30s \
        -s test_data.lua \
        "$SERVER_URL/api/sensor-data" \
        > "$RESULTS_DIR/wrk_sensor_data_${TIMESTAMP}.txt"
    
    # 传感器读写操作压测
    log_info "执行传感器读写操作压测..."
    wrk -t8 -c50 -d60s --timeout 30s \
        -s test_data.lua \
        "$SERVER_URL/api/sensor-rw" \
        > "$RESULTS_DIR/wrk_sensor_rw_${TIMESTAMP}.txt"
    
    # 批量操作压测
    log_info "执行批量传感器读写压测..."
    wrk -t6 -c30 -d60s --timeout 30s \
        -s test_data.lua \
        "$SERVER_URL/api/batch-sensor-rw" \
        > "$RESULTS_DIR/wrk_batch_rw_${TIMESTAMP}.txt"
    
    # 查询接口压测
    log_info "执行传感器数据查询压测..."
    wrk -t8 -c50 -d60s --timeout 30s \
        -s test_query_data.lua \
        "$SERVER_URL/api/get-sensor-data" \
        > "$RESULTS_DIR/wrk_query_data_${TIMESTAMP}.txt"
    
    log_success "wrk压测完成，结果保存在 $RESULTS_DIR"
}

# 运行hey压测
run_hey_test() {
    if ! check_tool hey; then
        log_warning "跳过hey测试"
        return
    fi
    
    log_info "运行hey压测..."
    
    # 健康检查压测
    log_info "执行健康检查压测..."
    hey -n 10000 -c 50 -t 30 \
        "$SERVER_URL/health" \
        > "$RESULTS_DIR/hey_health_${TIMESTAMP}.txt"
    
    # 传感器数据上报压测（使用POST）
    log_info "执行传感器数据上报压测..."
    cat > /tmp/sensor_data.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "device_id": "factory_001_device_001",
  "metric_name": "temperature",
  "value": 25.5,
  "priority": 1
}
EOF
    
    hey -n 5000 -c 100 -t 30 \
        -m POST \
        -H "Content-Type: application/json" \
        -D /tmp/sensor_data.json \
        "$SERVER_URL/api/sensor-data" \
        > "$RESULTS_DIR/hey_sensor_data_${TIMESTAMP}.txt"
    
    # 查询接口压测
    log_info "执行传感器数据查询压测..."
    cat > /tmp/query_data.json << EOF
{
  "device_id": "factory_001_device_001",
  "start_time": "2024-01-01T00:00:00Z",
  "end_time": "2024-12-31T23:59:59Z",
  "limit": 100
}
EOF
    
    hey -n 3000 -c 50 -t 30 \
        -m POST \
        -H "Content-Type: application/json" \
        -D /tmp/query_data.json \
        "$SERVER_URL/api/get-sensor-data" \
        > "$RESULTS_DIR/hey_query_data_${TIMESTAMP}.txt"
    
    log_success "hey压测完成，结果保存在 $RESULTS_DIR"
}

# 运行artillery压测
run_artillery_test() {
    if ! check_tool artillery; then
        log_warning "跳过artillery测试"
        return
    fi
    
    log_info "运行artillery压测..."
    
    artillery run artillery-load-test.yml \
        --output "$RESULTS_DIR/artillery_${TIMESTAMP}.json"
    
    # 生成HTML报告
    if [ -f "$RESULTS_DIR/artillery_${TIMESTAMP}.json" ]; then
        artillery report "$RESULTS_DIR/artillery_${TIMESTAMP}.json" \
            --output "$RESULTS_DIR/artillery_report_${TIMESTAMP}.html"
    fi
    
    log_success "artillery压测完成，结果保存在 $RESULTS_DIR"
}

# 运行k6压测
run_k6_test() {
    if ! check_tool k6; then
        log_warning "跳过k6测试"
        return
    fi
    
    log_info "运行k6压测..."
    
    k6 run k6-load-test.js \
        --out json="$RESULTS_DIR/k6_${TIMESTAMP}.json" \
        --summary-export="$RESULTS_DIR/k6_summary_${TIMESTAMP}.json"
    
    log_success "k6压测完成，结果保存在 $RESULTS_DIR"
}

# 生成综合报告
generate_summary_report() {
    log_info "生成综合报告..."
    
    cat > "$RESULTS_DIR/test_summary_${TIMESTAMP}.md" << EOF
# Bench Server 负载测试报告

**测试时间**: $(date)
**服务器地址**: $SERVER_URL
**测试工具**: $(ls $RESULTS_DIR/*_${TIMESTAMP}.* 2>/dev/null | wc -l) 个工具

## API接口概览

基于OpenAPI 3.0.3规范的时序数据存储系统，包含以下接口：

### 健康检查
- **GET /health** - 服务器健康状态检查

### 传感器数据接口
- **POST /api/sensor-data** - 单个传感器数据上报
- **POST /api/sensor-rw** - 传感器数据读写操作（包含事务）
- **POST /api/batch-sensor-rw** - 批量传感器数据读写操作
- **POST /api/get-sensor-data** - 传感器时序数据查询（支持时间范围和分页）

### 统计信息接口
- **GET /api/stats** - 系统统计信息查询

## 测试结果文件

$(ls -la $RESULTS_DIR/*_${TIMESTAMP}.* 2>/dev/null || echo "无测试结果文件")

## 业务逻辑特性

### 阈值监控
- 传感器数值超过100时自动触发告警
- 高值自动提升优先级为1（高优先级）
- 更新设备状态表记录告警次数

### 事务处理
- 所有读写操作在事务中完成
- 确保数据一致性和完整性
- 失败时自动回滚

### 批量处理
- 支持最多1000条记录的批量处理
- 每个记录独立处理并返回详细结果
- 统计总处理数量和告警数量

## 性能指标阈值

- **响应时间**: P50 < 50ms, P95 < 200ms, P99 < 500ms
- **错误率**: < 0.1%
- **吞吐量**: > 5000 QPS
- **资源使用**: CPU < 80%, 内存 < 2GB

EOF

    log_success "综合报告已生成：$RESULTS_DIR/test_summary_${TIMESTAMP}.md"
}

# 清理临时文件
cleanup() {
    rm -f /tmp/sensor_data.json
    log_info "清理完成"
}

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --help          显示此帮助信息
    -a, --all           运行所有可用的压测工具
    -w, --wrk           仅运行wrk压测
    -e, --hey           仅运行hey压测
    -r, --artillery     仅运行artillery压测
    -k, --k6            仅运行k6压测
    -c, --check         仅检查服务器状态和工具安装情况
    -s, --server URL    指定服务器地址 (默认: $SERVER_URL)

示例:
    $0 -a                    # 运行所有压测
    $0 -w -e                 # 仅运行wrk和hey压测
    $0 -s http://prod:8080   # 指定生产服务器地址
    $0 -c                    # 检查环境

压测工具安装:
    # wrk
    brew install wrk          # macOS
    sudo apt install wrk      # Ubuntu
    
    # hey
    go install github.com/rakyll/hey@latest
    
    # artillery
    npm install -g artillery
    
    # k6
    brew install k6           # macOS
    sudo snap install k6      # Ubuntu

EOF
}

# 主函数
main() {
    local run_all=false
    local run_wrk=false
    local run_hey=false
    local run_artillery=false
    local run_k6=false
    local check_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -w|--wrk)
                run_wrk=true
                shift
                ;;
            -e|--hey)
                run_hey=true
                shift
                ;;
            -r|--artillery)
                run_artillery=true
                shift
                ;;
            -k|--k6)
                run_k6=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -s|--server)
                SERVER_URL="$2"
                shift 2
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 如果没有指定任何工具，默认运行所有
    if [[ "$run_all" == false && "$run_wrk" == false && "$run_hey" == false && "$run_artillery" == false && "$run_k6" == false && "$check_only" == false ]]; then
        run_all=true
    fi
    
    log_info "开始Bench Server负载测试"
    log_info "目标服务器: $SERVER_URL"
    log_info "结果目录: $RESULTS_DIR"
    
    # 检查服务器状态
    if ! check_server; then
        exit 1
    fi
    
    # 如果只是检查模式
    if [[ "$check_only" == true ]]; then
        log_info "检查压测工具安装状态..."
        check_tool wrk
        check_tool hey
        check_tool artillery
        check_tool k6
        exit 0
    fi
    
    # 注册清理函数
    trap cleanup EXIT
    
    # 运行压测
    if [[ "$run_all" == true || "$run_wrk" == true ]]; then
        run_wrk_test
    fi
    
    if [[ "$run_all" == true || "$run_hey" == true ]]; then
        run_hey_test
    fi
    
    if [[ "$run_all" == true || "$run_artillery" == true ]]; then
        run_artillery_test
    fi
    
    if [[ "$run_all" == true || "$run_k6" == true ]]; then
        run_k6_test
    fi
    
    # 生成综合报告
    generate_summary_report
    
    log_success "所有压测完成！"
    log_info "查看结果: ls -la $RESULTS_DIR/"
    log_info "查看综合报告: cat $RESULTS_DIR/test_summary_${TIMESTAMP}.md"
}

# 执行主函数
main "$@" 