# Bench Server 负载测试文档

本文档基于 OpenAPI 3.0.3 规范，为 Bench Server 时序数据存储系统提供完整的负载测试解决方案。

## 📋 目录

- [API 接口概览](#api-接口概览)
- [文件说明](#文件说明)
- [快速开始](#快速开始)
- [压测工具详细说明](#压测工具详细说明)
- [性能指标](#性能指标)
- [测试场景](#测试场景)
- [故障排查](#故障排查)

## 🚀 API 接口概览

### 健康检查
```
GET /health
```
检查服务器和数据库连接状态

### 传感器数据接口
```
POST /api/sensor-data        # 单个传感器数据上报
POST /api/sensor-rw          # 传感器读写操作（包含事务）
POST /api/batch-sensor-rw    # 批量传感器读写操作
```

### 统计信息接口
```
GET /api/stats               # 系统统计信息查询
```

## 📁 文件说明

### OpenAPI 规范文档
- **`openapi.yaml`** - 完整的 OpenAPI 3.0.3 规范文档
- **`load_test_config.yaml`** - 压测配置文件（支持多种工具）

### 压测脚本
- **`run_load_tests.sh`** - 主压测执行脚本（一键执行）
- **`artillery-load-test.yml`** - Artillery 压测配置
- **`artillery-processor.js`** - Artillery 自定义处理器
- **`k6-load-test.js`** - K6 压测脚本

### 现有工具（复用）
- **`test_data.lua`** - wrk 脚本（已有）
- **`benchmark.sh`** - 基础压测脚本（已有）

## 🏃‍♂️ 快速开始

### 1. 启动服务器
```bash
# 启动 Bench Server
go run .
```

### 2. 检查环境
```bash
# 检查服务器状态和压测工具
./run_load_tests.sh --check
```

### 3. 运行压测
```bash
# 运行所有可用的压测工具
./run_load_tests.sh --all

# 或选择特定工具
./run_load_tests.sh --wrk          # 仅 wrk
./run_load_tests.sh --k6           # 仅 k6
./run_load_tests.sh --artillery    # 仅 artillery
```

### 4. 查看结果
```bash
# 查看结果目录
ls -la load_test_results/

# 查看综合报告
cat load_test_results/test_summary_*.md
```

## 🔧 压测工具详细说明

### 1. wrk (推荐用于基础压测)

**安装:**
```bash
# macOS
brew install wrk

# Ubuntu
sudo apt install wrk
```

**使用:**
```bash
./run_load_tests.sh --wrk
```

**特点:**
- 轻量级，高性能
- 支持 Lua 脚本自定义
- 适合快速基础压测

### 2. K6 (推荐用于专业压测)

**安装:**
```bash
# macOS
brew install k6

# Ubuntu
sudo snap install k6
```

**使用:**
```bash
./run_load_tests.sh --k6

# 或直接运行
k6 run k6-load-test.js
```

**特点:**
- 功能丰富，专业级
- 支持复杂测试场景
- 详细的性能指标
- 生成 HTML 报告

### 3. Artillery (推荐用于复杂场景)

**安装:**
```bash
npm install -g artillery
```

**使用:**
```bash
./run_load_tests.sh --artillery

# 或直接运行
artillery run artillery-load-test.yml
```

**特点:**
- 支持复杂的多阶段压测
- 丰富的验证功能
- WebSocket 支持
- 实时监控

### 4. hey (简单快速)

**安装:**
```bash
go install github.com/rakyll/hey@latest
```

**使用:**
```bash
./run_load_tests.sh --hey
```

**特点:**
- 简单易用
- 快速启动
- 基础功能完善

## 📊 性能指标

### 响应时间阈值
- **P50**: < 50ms
- **P95**: < 200ms  
- **P99**: < 500ms

### 错误率阈值
- **最大错误率**: < 0.1%

### 吞吐量阈值
- **最小 QPS**: > 5000

### 资源使用阈值
- **CPU**: < 80%
- **内存**: < 2GB

## 🎯 测试场景

### 基础负载分布
- **健康检查**: 5%
- **传感器数据上报**: 40%
- **传感器读写操作**: 35%
- **批量读写操作**: 15%
- **统计查询**: 5%

### 压测阶段
1. **预热阶段** (30s) - 低负载预热
2. **正常负载** (2m) - 模拟日常流量
3. **高负载** (2m) - 模拟繁忙时段
4. **峰值负载** (1m) - 模拟流量峰值
5. **降低负载** (2m) - 逐步减少负载
6. **冷却阶段** (30s) - 系统恢复

### 业务逻辑测试

#### 阈值监控测试
- 传感器数值 > 100 触发告警
- 自动提升优先级为 1
- 验证告警消息格式

#### 事务处理测试
- 读写操作原子性
- 失败回滚验证
- 并发事务处理

#### 批量处理测试
- 批量大小限制 (最多 1000 条)
- 每条记录独立处理
- 统计信息准确性

## 🛠️ 故障排查

### 常见问题

#### 1. 服务器连接失败
```bash
# 检查服务器状态
curl http://localhost:8080/health

# 检查端口占用
lsof -i :8080
```

#### 2. 压测工具未安装
```bash
# 检查工具安装状态
./run_load_tests.sh --check

# 安装缺失工具（参考上面的安装说明）
```

#### 3. 数据库连接问题
```bash
# 检查 MySQL 服务
brew services list | grep mysql  # macOS
sudo systemctl status mysql      # Linux

# 检查数据库配置
# 确认 DB_HOST, DB_PORT, DB_USER, DB_PASSWORD 环境变量
```

#### 4. 内存不足
```bash
# 监控资源使用
top -p $(pgrep bench_server)

# 调整压测参数
# 减少并发连接数和请求频率
```

### 性能调优建议

#### 数据库优化
```sql
-- 添加索引
CREATE INDEX idx_device_timestamp ON time_series_data(device_id, timestamp);
CREATE INDEX idx_metric_timestamp ON time_series_data(metric_name, timestamp);

-- 分区表优化（按时间分区）
-- 参考 database.go 中的分区配置
```

#### 应用优化
- 调整数据库连接池大小
- 启用 Go runtime 性能分析
- 使用 pprof 分析性能瓶颈

```bash
# 启用性能分析
go tool pprof http://localhost:8080/debug/pprof/profile
```

## 📈 结果分析

### 报告文件说明

#### wrk 结果
- `wrk_*_timestamp.txt` - wrk 原始输出
- 关注: Requests/sec, Latency Distribution

#### K6 结果  
- `k6_timestamp.json` - 详细指标数据
- `k6-load-test-report.html` - 可视化报告
- 关注: http_req_duration, http_req_failed 指标

#### Artillery 结果
- `artillery_timestamp.json` - 测试数据
- `artillery_report_timestamp.html` - HTML 报告
- 关注: Response time percentiles, Error rates

### 综合分析
```bash
# 查看综合报告
cat load_test_results/test_summary_*.md

# 对比不同工具结果
grep -r "Requests/sec\|QPS\|RPS" load_test_results/
```

## 🚀 高级用法

### 自定义压测场景

#### 修改 K6 脚本
```javascript
// 在 k6-load-test.js 中调整测试参数
export let options = {
  stages: [
    { duration: '5m', target: 500 },  // 自定义负载
  ],
};
```

#### 修改 Artillery 配置
```yaml
# 在 artillery-load-test.yml 中调整
phases:
  - duration: 300
    arrivalRate: 1000  # 自定义到达率
```

### 生产环境压测

```bash
# 指定生产服务器
./run_load_tests.sh --server https://prod.example.com:8080 --k6

# 使用环境变量
export BENCH_SERVER_URL="https://prod.example.com:8080"
./run_load_tests.sh --all
```

### 持续集成

```yaml
# .github/workflows/load-test.yml
name: Load Test
on: [push]
jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: |
          # 启动服务
          go run . &
          sleep 10
          # 运行压测
          ./run_load_tests.sh --k6
```

## 📞 支持与反馈

如果您在使用过程中遇到问题，请：

1. 查看本文档的故障排查部分
2. 检查 GitHub Issues
3. 提交新的 Issue 并附上：
   - 错误信息
   - 系统环境
   - 复现步骤

---

**Happy Load Testing! 🎯** 