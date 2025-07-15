# Bench Server 使用指南

## 概述

这是一个高性能的Go传感器数据处理服务器，提供传感器数据上报、读写操作、批量处理和统计查询等功能。支持配置文件和环境变量两种配置方式。

## 系统要求

- Go 1.21+
- MySQL 8.0+
- curl (用于测试)
- jq (可选，用于JSON格式化)

## 配置系统

### 配置优先级 (从高到低)
1. **环境变量** - 最高优先级
2. **配置文件** - 中等优先级  
3. **默认值** - 最低优先级

### 配置文件

默认配置文件为 `config.yaml`，你也可以通过 `CONFIG_PATH` 环境变量指定自定义配置文件路径。

**配置文件示例 (config.yaml):**
```yaml
# 服务器配置
server:
  port: "8080"

# 数据库配置
database:
  host: "localhost"
  port: "3306"
  user: "root"
  password: "root"
  name: "bench_server"
  max_open_conns: 25
  max_idle_conns: 5

# 日志配置
logging:
  level: "info"      # debug, info, warn, error
  format: "json"     # json, text

# 应用配置
app:
  read_timeout: "15s"
  write_timeout: "15s"
  idle_timeout: "60s"
```

### 环境变量

以下环境变量可以覆盖配置文件设置：

- `CONFIG_PATH`: 自定义配置文件路径 (默认: config.yaml)
- `PORT`: 服务器端口
- `DB_HOST`: 数据库主机
- `DB_PORT`: 数据库端口
- `DB_USER`: 数据库用户名
- `DB_PASSWORD`: 数据库密码
- `DB_NAME`: 数据库名称

## 快速启动

### 方式1: 使用配置文件

1. **创建配置文件**
```bash
cp config.yaml my_config.yaml
# 编辑 my_config.yaml 修改配置
```

2. **编译和运行**
```bash
go build -o bench-server
./bench-server                           # 使用默认配置文件
CONFIG_PATH=my_config.yaml ./bench-server # 使用自定义配置文件
```

### 方式2: 使用环境变量

```bash
export DB_HOST="localhost"
export DB_PORT="3306"
export DB_USER="root"
export DB_PASSWORD="your_mysql_password"
export DB_NAME="bench_server"
export PORT="8080"

./bench-server
```

### 方式3: 混合模式 (推荐)

使用配置文件设置基础配置，用环境变量覆盖特定设置：

```bash
# 使用配置文件，但用环境变量覆盖端口和密码
PORT=9000 DB_PASSWORD=secret ./bench-server
```

## 配置测试

运行配置系统测试：
```bash
./test_config.sh
```

这将测试：
- 配置文件读取
- 环境变量覆盖
- 自定义配置文件
- 无配置文件情况

## API 端点

### 1. 健康检查
```bash
curl http://localhost:8080/health
```

**响应:**
```json
{
  "status": "healthy",
  "time": "2025-07-15T20:18:46+08:00"
}
```

### 2. 传感器数据上报
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "timestamp":"2024-01-15T10:30:00.000Z",
    "device_id":"device001",
    "metric_name":"temperature",
    "value":25.8,
    "priority":1,
    "data":"sensor payload data"
  }' \
  http://localhost:8080/api/sensor-data
```

**响应:**
```json
{
  "message": "Data inserted successfully",
  "status": "success"
}
```

### 3. 传感器读写操作
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "device_id":"device001",
    "metric_name":"temperature",
    "new_value":26.5,
    "timestamp":"2024-01-15T10:35:00.000Z",
    "priority":2,
    "data":"write operation"
  }' \
  http://localhost:8080/api/sensor-rw
```

**响应:**
```json
{
  "device_id": "device001",
  "metric_name": "temperature",
  "new_value": 26.5,
  "previous_value": 25.8,
  "priority": 2,
  "status": "success",
  "timestamp": "2024-01-15T10:35:00.000Z"
}
```

### 4. 批量传感器读写操作
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "data":[
      {
        "device_id":"device001",
        "metric_name":"humidity",
        "new_value":65.2,
        "timestamp":"2024-01-15T10:40:00.000Z",
        "priority":2,
        "data":"batch test 1"
      },
      {
        "device_id":"device002",
        "metric_name":"temperature",
        "new_value":27.1,
        "timestamp":"2024-01-15T10:40:01.000Z",
        "priority":1,
        "data":"batch test 2"
      }
    ]
  }' \
  http://localhost:8080/api/batch-sensor-rw
```

### 5. 统计信息查询
```bash
curl http://localhost:8080/api/stats
```

**响应:**
```json
{
  "device_count": 7,
  "priority_stats": {
    "1": 5,
    "2": 6
  },
  "recent_24h_count": 11,
  "total_alerts": 1,
  "total_records": 11
}
```

### 6. 获取传感器数据
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "device_id":"device001",
    "metric_name":"temperature",
    "start_time":"2024-01-01T00:00:00.000Z",
    "end_time":"2024-12-31T23:59:59.000Z",
    "limit":10
  }' \
  http://localhost:8080/api/get-sensor-data
```

## 数据结构

### 传感器数据字段
- `timestamp`: ISO 8601格式的时间戳
- `device_id`: 设备唯一标识符
- `metric_name`: 指标名称（如temperature, humidity等）
- `value`/`new_value`: 传感器值
- `priority`: 优先级（1=高, 2=中, 3=低）
- `data`: 附加数据载荷

## 测试脚本

项目包含几个测试脚本：

1. **综合API测试**: `./test_all_apis.sh`
2. **配置系统测试**: `./test_config.sh`
3. **负载测试**: 查看 `LOAD_TESTING_README.md`

## 性能特性

- 使用连接池优化数据库性能
- 支持事务操作确保数据一致性
- 提供批量操作减少网络开销
- 结构化日志记录（支持JSON和文本格式）
- 优雅关闭支持
- 灵活的配置系统

## 数据库表结构

### time_series_data
存储时序传感器数据

### device_status
存储设备当前状态

### data_statistics
存储系统统计信息

## 故障排除

### 1. 数据库连接失败
- 检查MySQL服务是否运行
- 验证数据库配置（主机、端口、用户名、密码）
- 检查数据库是否存在

### 2. 端口被占用
- 修改配置文件中的端口设置
- 或使用环境变量 `PORT=新端口` 覆盖
- 停止占用进程

### 3. 编译错误
- 确保Go版本>=1.21
- 运行 `go mod tidy` 更新依赖

### 4. 配置文件问题
- 检查YAML语法是否正确
- 验证配置文件路径
- 查看启动日志中的警告信息

## 配置示例

### 开发环境配置
```yaml
server:
  port: "8080"
database:
  host: "localhost"
  password: "dev_password"
logging:
  level: "debug"
  format: "text"
```

### 生产环境配置
```yaml
server:
  port: "80"
database:
  host: "prod-db-server"
  max_open_conns: 100
  max_idle_conns: 20
logging:
  level: "info"
  format: "json"
app:
  read_timeout: "30s"
  write_timeout: "30s"
```

## 开发和扩展

代码结构：
- `main.go`: 主程序和服务器配置
- `database.go`: 数据库操作和初始化
- `handlers.go`: HTTP处理器和API逻辑
- `utils.go`: 工具函数
- `writer.go`: 专用写入优化
- `config.yaml`: 默认配置文件

系统支持水平扩展和高并发处理，适合IoT传感器数据收集场景。 