-- Wrk 压测脚本 - 支持传感器数据接口
-- 支持: /api/sensor-data, /api/sensor-rw, /api/batch-sensor-rw

-- 初始化随机种子
math.randomseed(os.time())

-- 测试数据池
local factories = {"001", "002", "003", "004", "005"}
local metrics = {"temperature", "pressure", "humidity", "vibration", "voltage", "current", "power", "flow_rate"}
local priorities = {1, 2, 3}

-- 生成随机负载数据的函数
function generateRandomPayload(targetSize)
    targetSize = targetSize or 1024
    
    -- 生成负载数据结构
    local load = {}
    for i = 1, 50 do
        table.insert(load, math.random(10000))
    end
    
    local sequence = {}
    for i = 1, 30 do
        table.insert(sequence, math.random() * 1000)
    end
    
    local payload = {
        load = load,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        size = targetSize,
        random = generateRandomString(200),
        sequence = sequence,
        metadata = string.format("generated_at_%d_device_simulation_data_for_load_testing", os.time())
    }
    
    -- 序列化为JSON字符串
    local jsonStr = jsonEncode(payload)
    
    -- 如果需要填充到目标大小
    if #jsonStr < targetSize then
        local padding = string.rep("_LOAD_TEST_PADDING_DATA_", math.ceil((targetSize - #jsonStr) / 24))
        payload.metadata = payload.metadata .. padding:sub(1, targetSize - #jsonStr)
        jsonStr = jsonEncode(payload)
    end
    
    -- 返回base64编码的字符串
    return base64encode(jsonStr)
end

-- 生成随机字符串
function generateRandomString(length)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local result = ""
    for i = 1, length do
        local idx = math.random(#chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- 简单的JSON编码
function jsonEncode(obj)
    if type(obj) == "table" then
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(obj) do
            if type(k) ~= "number" or k <= 0 or k ~= math.floor(k) then
                isArray = false
                break
            end
            maxIndex = math.max(maxIndex, k)
        end
        
        if isArray then
            local items = {}
            for i = 1, maxIndex do
                table.insert(items, jsonEncode(obj[i] or "null"))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local items = {}
            for k, v in pairs(obj) do
                table.insert(items, '"' .. tostring(k) .. '":' .. jsonEncode(v))
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    elseif type(obj) == "string" then
        return '"' .. obj:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
    elseif type(obj) == "number" then
        return tostring(obj)
    elseif type(obj) == "boolean" then
        return obj and "true" or "false"
    else
        return "null"
    end
end

-- 简单的base64编码
function base64encode(data)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = ""
    local padding = ""
    
    -- 简化版base64编码
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i+2)
        b = b or 0
        c = c or 0
        
        local bitmap = (a << 16) + (b << 8) + c
        
        result = result .. chars:sub(((bitmap >> 18) & 63) + 1, ((bitmap >> 18) & 63) + 1)
        result = result .. chars:sub(((bitmap >> 12) & 63) + 1, ((bitmap >> 12) & 63) + 1)
        result = result .. (i + 1 <= #data and chars:sub(((bitmap >> 6) & 63) + 1, ((bitmap >> 6) & 63) + 1) or "=")
        result = result .. (i + 2 <= #data and chars:sub((bitmap & 63) + 1, (bitmap & 63) + 1) or "=")
    end
    
    return result
end

-- 生成传感器数据
function generateSensorData()
    local factory = factories[math.random(#factories)]
    local device_id = factory .. "_device_" .. string.format("%03d", math.random(200))
    local metric = metrics[math.random(#metrics)]
    local value = math.random() * 150  -- 可能超过阈值100
    local priority = priorities[math.random(#priorities)]
    
    -- 生成不同大小的负载数据
    local payloadSize = 1024  -- 默认1KB
    local rand = math.random()
    if rand < 0.3 then
        payloadSize = 512    -- 30% 小负载 (512B)
    elseif rand < 0.6 then
        payloadSize = 2048   -- 30% 中等负载 (2KB)
    elseif rand < 0.9 then
        payloadSize = 8192   -- 30% 大负载 (8KB)
    else
        payloadSize = 20480  -- 10% 超大负载 (20KB)
    end
    
    local body = string.format(
        '{"timestamp":"%s","device_id":"%s","metric_name":"%s","value":%.2f,"priority":%d,"data":"%s"}',
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        device_id,
        metric,
        value,
        priority,
        generateRandomPayload(payloadSize)
    )
    
    return body
end

-- 生成传感器读写数据
function generateSensorRWData()
    local factory = factories[math.random(#factories)]
    local device_id = factory .. "_device_" .. string.format("%03d", math.random(100))
    local metric = metrics[math.random(#metrics)]
    local value = math.random() * 150  -- 可能超过阈值100
    local priority = priorities[math.random(#priorities)]
    
    -- 生成负载数据
    local payloadSize = math.random(1024, 5120)  -- 1-5KB随机大小
    
    local body = string.format(
        '{"device_id":"%s","metric_name":"%s","new_value":%.2f,"timestamp":"%s","priority":%d,"data":"%s"}',
        device_id,
        metric,
        value,
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        priority,
        generateRandomPayload(payloadSize)
    )
    
    return body
end

-- 生成批量传感器读写数据
function generateBatchSensorRWData()
    local batchSize = math.random(5, 20)  -- 随机批量大小5-20
    local dataArray = {}
    
    for i = 1, batchSize do
        local factory = factories[math.random(#factories)]
        local device_id = factory .. "_device_" .. string.format("%03d", math.random(200))
        local metric = metrics[math.random(#metrics)]
        local value = math.random() * 150  -- 可能超过阈值100
        local priority = priorities[math.random(#priorities)]
        
        -- 批量操作中使用较小的负载数据以避免请求过大
        local payloadSize = math.random(256, 1024)  -- 256B-1KB
        
        local dataItem = string.format(
            '{"device_id":"%s","metric_name":"%s","new_value":%.2f,"timestamp":"%s","priority":%d,"data":"%s"}',
            device_id,
            metric,
            value,
            os.date("!%Y-%m-%dT%H:%M:%SZ"),
            priority,
            generateRandomPayload(payloadSize)
        )
        
        table.insert(dataArray, dataItem)
    end
    
    local body = string.format('{"data":[%s]}', table.concat(dataArray, ","))
    return body
end

-- 请求函数
request = function()
    local path = wrk.path
    local method = wrk.method
    
    if path == "/api/sensor-data" then
        -- 传感器数据接口
        local body = generateSensorData()
        return wrk.format("POST", "/api/sensor-data", {["Content-Type"] = "application/json"}, body)
    elseif path == "/api/sensor-rw" then
        -- 传感器读写接口
        local body = generateSensorRWData()
        return wrk.format("POST", "/api/sensor-rw", {["Content-Type"] = "application/json"}, body)
    elseif path == "/api/batch-sensor-rw" then
        -- 批量传感器读写接口
        local body = generateBatchSensorRWData()
        return wrk.format("POST", "/api/batch-sensor-rw", {["Content-Type"] = "application/json"}, body)
    else
        -- 默认返回传感器数据
        local body = generateSensorData()
        return wrk.format("POST", "/api/sensor-data", {["Content-Type"] = "application/json"}, body)
    end
end

-- 响应处理
response = function(status, headers, body)
    if status ~= 200 then
        print("Error status: " .. status)
        print("Response body: " .. body)
    end
end

-- 完成处理
done = function(summary, latency, requests)
    print("=== Wrk 压测结果汇总 ===")
    print(string.format("请求总数: %d", summary.requests))
    print(string.format("总耗时: %.2f秒", summary.duration / 1000000))
    print(string.format("平均QPS: %.2f", summary.requests / (summary.duration / 1000000)))
    print(string.format("错误数: %d", summary.errors.connect + summary.errors.read + summary.errors.write + summary.errors.status + summary.errors.timeout))
    print(string.format("平均延迟: %.2fms", latency.mean / 1000))
    print(string.format("P50延迟: %.2fms", latency:percentile(50) / 1000))
    print(string.format("P95延迟: %.2fms", latency:percentile(95) / 1000))
    print(string.format("P99延迟: %.2fms", latency:percentile(99) / 1000))
    print("========================")
end 