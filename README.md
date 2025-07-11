# Bench Server - 时序数据存储系统

基于Go语言实现的高性能时序数据存储HTTP服务器，支持MySQL持久化存储。

## 功能特性

### 核心API接口
- `POST /api/sensor-data` - 传感器数据上报
- `POST /api/sensor-rw` - 传感器数据读写操作（开启事务）
- `POST /api/batch-sensor-rw` - 批量传感器数据读写操作（开启事务）
- `POST /api/get-sensor-data` - 传感器时序数据查询（支持时间范围和分页）
- `GET /api/stats` - 系统统计信息
- `GET /health` - 健康检查

### 性能优化特性
- 批量写入优化
- 数据压缩支持
- 优先级队列处理
- 连接池管理
- 事务优化

## 快速开始

### 1. 环境要求
- Go 1.21+
- MySQL 8.0+
- wrk (用于压测)

### 2. 安装依赖
```bash
go mod tidy
```

### 3. 配置数据库
```bash
# 创建数据库
mysql -u root -p -e "CREATE DATABASE bench_server CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# 设置环境变量
export DB_HOST=localhost
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=your_password
export DB_NAME=bench_server
```

### 4. 启动服务器
```bash
go run .
```

服务器将在 `http://localhost:8080` 启动。

## 压测指南

### 1. 安装wrk
```bash
# macOS
brew install wrk

# Ubuntu/Debian
sudo apt-get install wrk

# 或从源码编译
git clone https://github.com/wg/wrk.git
cd wrk
make
```

### 2. 运行压测

#### 传感器数据压测
```bash
# 基准测试：100并发，持续60秒
wrk -t12 -c100 -d60s -s test_data.lua http://localhost:8080/api/sensor-data

# 高并发测试：1000并发，持续30秒
wrk -t20 -c1000 -d30s -s test_data.lua http://localhost:8080/api/sensor-data

# 目标QPS测试：指定RPS
wrk -t10 -c100 -d60s -R10000 -s test_data.lua http://localhost:8080/api/sensor-data
```

#### 传感器读写操作压测
```bash
# 传感器读写测试
wrk -t12 -c100 -d60s -s test_data.lua http://localhost:8080/api/sensor-rw

# 批量传感器读写测试
wrk -t12 -c100 -d60s -s test_data.lua http://localhost:8080/api/batch-sensor-rw

# 传感器数据查询测试
wrk -t8 -c50 -d60s -s test_query_data.lua http://localhost:8080/api/get-sensor-data
```

### 3. 使用hey进行压测
```bash
# 安装hey
go install github.com/rakyll/hey@latest

# 传感器数据压测
hey -n 100000 -c 100 -m POST -H "Content-Type: application/json" \
    -d '{"timestamp":"2024-01-01T10:00:00Z","device_id":"factory_001_device_001","metric_name":"temperature","value":23.5,"priority":1}' \
    http://localhost:8080/api/sensor-data

# 传感器读写操作压测
hey -n 100000 -c 100 -m POST -H "Content-Type: application/json" \
    -d '{"device_id":"factory_001_device_001","metric_name":"temperature","new_value":105.5,"timestamp":"2024-01-01T10:00:00Z","priority":1}' \
    http://localhost:8080/api/sensor-rw

# 批量传感器读写操作压测
hey -n 100000 -c 100 -m POST -H "Content-Type: application/json" \
    -d '{"data":[{"device_id":"factory_001_device_001","metric_name":"temperature","new_value":105.5,"timestamp":"2024-01-01T10:00:00Z","priority":1},{"device_id":"factory_001_device_002","metric_name":"pressure","new_value":85.3,"timestamp":"2024-01-01T10:00:01Z","priority":2}]}' \
    http://localhost:8080/api/batch-sensor-rw

# 传感器数据查询压测
hey -n 50000 -c 50 -m POST -H "Content-Type: application/json" \
    -d '{"device_id":"factory_001_device_001","start_time":"2024-01-01T00:00:00Z","end_time":"2024-12-31T23:59:59Z","limit":100}' \
    http://localhost:8080/api/get-sensor-data

# 持续压测
hey -z 60s -c 100 -m POST -H "Content-Type: application/json" \
    -d '{"timestamp":"2024-01-01T10:00:00Z","device_id":"factory_001_device_001","metric_name":"temperature","value":23.5,"priority":1}' \
    http://localhost:8080/api/sensor-data
```

## API使用示例

### 1. 传感器数据上报
```bash
curl -X POST http://localhost:8080/api/sensor-data \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2024-01-01T10:00:00Z",
    "device_id": "factory_001_device_001",
    "metric_name": "temperature",
    "value": 23.5,
    "priority": 1
  }'
```

### 2. 传感器数据读写操作（开启事务）
```bash
curl -X POST http://localhost:8080/api/sensor-rw \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "metric_name": "temperature",
    "new_value": 105.5,
    "timestamp": "2024-01-01T10:00:00Z",
    "priority": 1
  }'
```

这个接口会：
1. 读取当前设备的最新值
2. 检查新值是否超过阈值（100）
3. 如果超过阈值，自动提升优先级并记录告警
4. 插入新记录
5. 更新设备状态表
6. 所有操作在事务中完成

### 3. 批量传感器数据读写操作
```bash
curl -X POST http://localhost:8080/api/batch-sensor-rw \
  -H "Content-Type: application/json" \
  -d '{
    "data": [
      {
        "device_id": "factory_001_device_001",
        "metric_name": "temperature",
        "new_value": 105.5,
        "timestamp": "2024-01-01T10:00:00Z",
        "priority": 1
      },
      {
        "device_id": "factory_001_device_002",
        "metric_name": "pressure",
        "new_value": 85.3,
        "timestamp": "2024-01-01T10:00:01Z",
        "priority": 2
      },
      {
        "device_id": "factory_001_device_003",
        "metric_name": "voltage",
        "new_value": 120.8,
        "timestamp": "2024-01-01T10:00:02Z",
        "priority": 1
      }
    ]
  }'
```

这个接口会：
1. 批量处理多个传感器数据
2. 每个数据项都执行读写操作
3. 所有操作在同一个事务中完成
4. 返回每个数据项的处理结果
5. 统计总处理数量和告警数量

### 4. 传感器数据查询
```bash
# 查询设备所有指标
curl -X POST http://localhost:8080/api/get-sensor-data \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 100
  }'

# 查询特定指标
curl -X POST http://localhost:8080/api/get-sensor-data \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "metric_name": "temperature",
    "start_time": "2024-01-01T10:00:00Z",
    "end_time": "2024-01-01T11:00:00Z",
    "limit": 50
  }'

# 分页查询
curl -X POST http://localhost:8080/api/get-sensor-data \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "factory_001_device_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "limit": 20,
    "offset": 10
  }'
```

这个接口支持：
- 按设备ID查询历史数据
- 时间范围过滤（start_time 到 end_time）
- 可选择特定指标类型（metric_name）
- 分页查询（limit, offset）
- 返回数据预览和完整统计信息
- 按时间倒序排列（最新数据在前）

### 5. 系统监控
```bash
# 健康检查
curl http://localhost:8080/health

# 统计信息
curl http://localhost:8080/api/stats
```

## 性能优化策略

### 1. 批量写入优化
- 使用缓冲池收集数据
- 定时刷新机制
- 事务批量提交

### 2. 数据压缩
- Gzip压缩支持
- 减少网络传输和存储空间

### 3. 优先级处理
- 高优先级数据快速处理
- 低优先级数据批量处理
- 差异化刷新间隔

### 4. 数据库优化
- 连接池管理
- 索引优化
- 分区表支持

## 配置说明

### 环境变量
- `PORT` - 服务器端口 (默认: 8080)
- `DB_HOST` - 数据库主机 (默认: localhost)
- `DB_PORT` - 数据库端口 (默认: 3306)
- `DB_USER` - 数据库用户名 (默认: root)
- `DB_PASSWORD` - 数据库密码
- `DB_NAME` - 数据库名称 (默认: bench_server)

### 数据库配置
- 最大连接数: 25
- 最大空闲连接: 5
- 连接生命周期: 1小时

## 监控指标

### 关键指标
- QPS (每秒查询数)
- P95/P99延迟
- 失败率
- 数据库连接数
- 内存使用率

### 统计信息
- 总记录数
- 按优先级统计
- 最近24小时数据量

## 故障排查

### 常见问题
1. 数据库连接失败
   - 检查数据库服务状态
   - 验证连接参数
   - 确认网络连通性

2. 性能问题
   - 检查数据库索引
   - 监控连接池使用情况
   - 分析慢查询日志

3. 内存泄漏
   - 监控内存使用趋势
   - 检查goroutine数量
   - 分析GC日志

## 开发指南

### 项目结构
```
.
├── main.go          # 主程序入口
├── database.go      # 数据库操作
├── handlers.go      # API处理函数
├── writer.go        # 高性能写入器
├── test_data.lua    # 压测脚本
├── go.mod           # Go模块文件
└── README.md        # 项目文档
```

### 扩展开发
1. 添加新的API接口
2. 实现自定义写入策略
3. 集成监控系统
4. 添加数据验证规则

## 许可证

MIT License 