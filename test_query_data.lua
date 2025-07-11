-- Wrk 压测脚本 - 专门用于传感器数据查询接口
-- 支持: /api/get-sensor-data

-- 初始化随机种子
math.randomseed(os.time())

-- 测试数据池
local factories = {"001", "002", "003", "004", "005"}
local metrics = {"temperature", "pressure", "humidity", "vibration", "voltage", "current", "power", "flow_rate"}
local device_ids = {}

-- 预生成设备ID列表
for _, factory in ipairs(factories) do
    for i = 1, 50 do
        table.insert(device_ids, factory .. "_device_" .. string.format("%03d", i))
    end
end

-- 生成时间范围
function generateTimeRange()
    local now = os.time()
    local timeRanges = {
        -- 最近1小时
        {
            start = os.date("!%Y-%m-%dT%H:%M:%SZ", now - 3600),
            end_time = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
        },
        -- 最近24小时
        {
            start = os.date("!%Y-%m-%dT%H:%M:%SZ", now - 86400),
            end_time = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
        },
        -- 最近7天
        {
            start = os.date("!%Y-%m-%dT%H:%M:%SZ", now - 604800),
            end_time = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
        },
        -- 最近30天
        {
            start = os.date("!%Y-%m-%dT%H:%M:%SZ", now - 2592000),
            end_time = os.date("!%Y-%m-%dT%H:%M:%SZ", now)
        },
        -- 自定义范围（2024年全年）
        {
            start = "2024-01-01T00:00:00Z",
            end_time = "2024-12-31T23:59:59Z"
        }
    }
    
    return timeRanges[math.random(#timeRanges)]
end

-- 生成查询参数
function generateQueryParams()
    local device_id = device_ids[math.random(#device_ids)]
    local timeRange = generateTimeRange()
    
    -- 决定查询类型
    local queryType = math.random()
    local params = {
        device_id = device_id,
        start_time = timeRange.start,
        end_time = timeRange.end_time
    }
    
    -- 40% 查询特定指标，60% 查询所有指标
    if queryType < 0.4 then
        params.metric_name = metrics[math.random(#metrics)]
    end
    
    -- 设置分页参数
    local limitOptions = {10, 50, 100, 500, 1000}
    params.limit = limitOptions[math.random(#limitOptions)]
    
    -- 20% 的请求使用偏移量（分页）
    if math.random() < 0.2 then
        params.offset = math.random(0, 100)
    end
    
    return params
end

-- 将参数转换为JSON字符串
function paramsToJson(params)
    local jsonParts = {}
    
    table.insert(jsonParts, '"device_id":"' .. params.device_id .. '"')
    table.insert(jsonParts, '"start_time":"' .. params.start_time .. '"')
    table.insert(jsonParts, '"end_time":"' .. params.end_time .. '"')
    
    if params.metric_name then
        table.insert(jsonParts, '"metric_name":"' .. params.metric_name .. '"')
    end
    
    table.insert(jsonParts, '"limit":' .. params.limit)
    
    if params.offset then
        table.insert(jsonParts, '"offset":' .. params.offset)
    end
    
    return "{" .. table.concat(jsonParts, ",") .. "}"
end

-- 生成查询请求
function generateQueryRequest()
    local params = generateQueryParams()
    return paramsToJson(params)
end

-- 请求计数器
local requestCount = 0

-- 初始化函数
function init(args)
    -- 设置请求头
    wrk.headers["Content-Type"] = "application/json"
    wrk.method = "POST"
    
    -- 设置目标路径
    wrk.path = "/api/get-sensor-data"
    
    print("查询接口压测脚本初始化完成")
    print("目标路径: " .. wrk.path)
    print("设备数量: " .. #device_ids)
    print("指标类型: " .. #metrics)
end

-- 生成每个请求
function request()
    requestCount = requestCount + 1
    
    local body = generateQueryRequest()
    
    -- 每1000个请求打印一次状态
    if requestCount % 1000 == 0 then
        print("已生成请求数: " .. requestCount)
    end
    
    return wrk.format("POST", wrk.path, wrk.headers, body)
end

-- 响应处理
function response(status, headers, body)
    -- 记录错误响应
    if status ~= 200 then
        print("错误响应: " .. status .. " - " .. body)
    end
    
    -- 可选：解析响应统计
    if status == 200 and body then
        -- 简单检查响应是否包含expected字段
        if string.find(body, '"status":"success"') then
            -- 成功响应
        else
            print("响应格式异常: " .. body:sub(1, 200))
        end
    end
end

-- 完成时的统计
function done(summary, latency, requests)
    print("\n========== 查询接口压测结果 ==========")
    print("总请求数: " .. summary.requests)
    print("总耗时: " .. summary.duration / 1000000 .. " 秒")
    print("平均QPS: " .. summary.requests / (summary.duration / 1000000))
    print("错误数: " .. summary.errors.connect + summary.errors.read + summary.errors.write + summary.errors.status + summary.errors.timeout)
    print("错误率: " .. string.format("%.2f%%", (summary.errors.connect + summary.errors.read + summary.errors.write + summary.errors.status + summary.errors.timeout) / summary.requests * 100))
    
    print("\n延迟统计:")
    print("P50: " .. latency:percentile(50) / 1000 .. " ms")
    print("P90: " .. latency:percentile(90) / 1000 .. " ms")
    print("P95: " .. latency:percentile(95) / 1000 .. " ms")
    print("P99: " .. latency:percentile(99) / 1000 .. " ms")
    print("最大延迟: " .. latency.max / 1000 .. " ms")
    
    print("\n请求分布:")
    for i = 1, #requests do
        local bucket = requests[i]
        print(string.format("%4d ms: %d 个请求", bucket.duration / 1000, bucket.count))
    end
    
    print("\n========== 压测完成 ==========")
end 