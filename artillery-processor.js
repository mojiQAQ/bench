/**
 * Artillery 处理器 - 自定义函数和数据生成
 */

const crypto = require('crypto');

// 测试数据
const factories = ['001', '002', '003', '004', '005'];
const metrics = ['temperature', 'pressure', 'humidity', 'vibration', 'voltage', 'current', 'power', 'flow_rate'];
const priorities = [1, 2, 3];

// 工具函数
function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function randomFloat(min, max) {
  return parseFloat((Math.random() * (max - min) + min).toFixed(2));
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function generateDeviceId() {
  const factory = randomChoice(factories);
  const device = String(randomInt(1, 200)).padStart(3, '0');
  return `factory_${factory}_device_${device}`;
}

function generateTimestamp() {
  const now = new Date();
  const offset = Math.floor(Math.random() * 3600000); // 1小时内随机
  return new Date(now.getTime() - offset).toISOString();
}

// 生成随机字符串
function generateRandomString(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// 生成随机负载数据
function generateRandomPayload(targetSize = 1024) {
  // 限制大小在合理范围内
  if (targetSize > 65535) targetSize = 65535;
  if (targetSize < 256) targetSize = 256;
  
  const payload = {
    load: Array.from({length: 50}, () => randomInt(1, 10000)),
    timestamp: new Date().toISOString(),
    size: targetSize,
    random: generateRandomString(200),
    sequence: Array.from({length: 30}, () => randomFloat(0, 1000)),
    metadata: `generated_at_${Date.now()}_device_simulation_data_for_load_testing`
  };
  
  let jsonStr = JSON.stringify(payload);
  
  // 如果需要填充到目标大小
  if (jsonStr.length < targetSize) {
    const padding = '_LOAD_TEST_PADDING_DATA_'.repeat(Math.ceil((targetSize - jsonStr.length) / 24));
    payload.metadata += padding.substring(0, targetSize - jsonStr.length);
    jsonStr = JSON.stringify(payload);
  }
  
  // 返回base64编码
  return Buffer.from(jsonStr).toString('base64');
}

// 生成传感器数据
function generateSensorData(userContext, events, done) {
  // 生成不同大小的负载数据
  let payloadSize = 1024; // 默认1KB
  const rand = Math.random();
  if (rand < 0.3) {
    payloadSize = 512;    // 30% 小负载 (512B)
  } else if (rand < 0.6) {
    payloadSize = 2048;   // 30% 中等负载 (2KB)
  } else if (rand < 0.9) {
    payloadSize = 8192;   // 30% 大负载 (8KB)
  } else {
    payloadSize = 20480;  // 10% 超大负载 (20KB)
  }
  
  userContext.vars.sensorData = {
    timestamp: generateTimestamp(),
    device_id: generateDeviceId(),
    metric_name: randomChoice(metrics),
    value: randomFloat(10, 150),
    priority: randomChoice(priorities),
    data: generateRandomPayload(payloadSize)
  };
  
  return done();
}

// 生成传感器读写数据
function generateSensorRWData(userContext, events, done) {
  const payloadSize = randomInt(1024, 5120); // 1-5KB随机大小
  
  userContext.vars.sensorRWData = {
    device_id: generateDeviceId(),
    metric_name: randomChoice(metrics),
    new_value: randomFloat(20, 140),
    timestamp: generateTimestamp(),
    priority: randomChoice(priorities),
    data: generateRandomPayload(payloadSize)
  };
  
  return done();
}

// 生成批量数据
function generateBatchData(userContext, events, done) {
  const batchSize = randomInt(2, 5);
  const data = [];
  
  for (let i = 0; i < batchSize; i++) {
    // 批量操作中使用较小的负载数据以避免请求过大
    const payloadSize = randomInt(256, 1024); // 256B-1KB
    data.push({
      device_id: generateDeviceId(),
      metric_name: randomChoice(metrics),
      new_value: randomFloat(20, 140),
      timestamp: generateTimestamp(),
      priority: randomChoice(priorities),
      data: generateRandomPayload(payloadSize)
    });
  }
  
  userContext.vars.batchData = { data };
  return done();
}

// 验证响应
function validateSensorDataResponse(requestParams, response, context, ee, next) {
  if (response.statusCode !== 200) {
    ee.emit('error', `Sensor data response status: ${response.statusCode}`);
    return next();
  }
  
  try {
    const body = JSON.parse(response.body);
    if (body.status !== 'success') {
      ee.emit('error', `Sensor data response not successful: ${body.message || 'unknown error'}`);
    }
    
    // 检查是否包含payload数据
    const originalData = context.vars.sensorData;
    if (!originalData.data || originalData.data.length === 0) {
      ee.emit('error', 'Missing payload data in original request');
    }
    
  } catch (error) {
    ee.emit('error', `Failed to parse sensor data response: ${error.message}`);
  }
  
  return next();
}

function validateSensorRWResponse(requestParams, response, context, ee, next) {
  if (response.statusCode !== 200) {
    ee.emit('error', `Sensor RW response status: ${response.statusCode}`);
    return next();
  }
  
  try {
    const body = JSON.parse(response.body);
    if (body.status !== 'success') {
      ee.emit('error', `Sensor RW response not successful: ${body.message || 'unknown error'}`);
      return next();
    }
    
    // 验证数据
    const originalData = context.vars.sensorRWData;
    if (body.device_id !== originalData.device_id) {
      ee.emit('error', 'Device ID mismatch in sensor RW response');
    }
    
    if (Math.abs(body.new_value - originalData.new_value) > 0.01) {
      ee.emit('error', 'New value mismatch in sensor RW response');
    }
    
    // 检查是否包含payload数据
    if (!originalData.data || originalData.data.length === 0) {
      ee.emit('error', 'Missing payload data in original RW request');
    }
    
    // 检查告警逻辑
    if (originalData.new_value > 100 && (!body.alert || !body.alert.includes('High value alert'))) {
      ee.emit('error', 'Missing expected alert for high value');
    }
    
  } catch (error) {
    ee.emit('error', `Failed to parse sensor RW response: ${error.message}`);
  }
  
  return next();
}

function validateBatchResponse(requestParams, response, context, ee, next) {
  if (response.statusCode !== 200) {
    ee.emit('error', `Batch response status: ${response.statusCode}`);
    return next();
  }
  
  try {
    const body = JSON.parse(response.body);
    if (body.status !== 'success') {
      ee.emit('error', `Batch response not successful: ${body.message || 'unknown error'}`);
      return next();
    }
    
    // 验证处理数量
    const originalData = context.vars.batchData;
    if (body.total_processed !== originalData.data.length) {
      ee.emit('error', `Processed count mismatch: expected ${originalData.data.length}, got ${body.total_processed}`);
    }
    
    // 验证结果数组
    if (!body.results || body.results.length !== originalData.data.length) {
      ee.emit('error', 'Results array length mismatch');
    }
    
    // 检查所有原始数据都包含payload
    const allHavePayload = originalData.data.every(item => item.data && item.data.length > 0);
    if (!allHavePayload) {
      ee.emit('error', 'Some batch items missing payload data');
    }
    
    // 验证告警数量
    const expectedAlerts = originalData.data.filter(item => item.new_value > 100).length;
    if (body.total_alerts !== expectedAlerts) {
      ee.emit('error', `Alert count mismatch: expected ${expectedAlerts}, got ${body.total_alerts}`);
    }
    
  } catch (error) {
    ee.emit('error', `Failed to parse batch response: ${error.message}`);
  }
  
  return next();
}

function validateStatsResponse(requestParams, response, context, ee, next) {
  if (response.statusCode !== 200) {
    ee.emit('error', `Stats response status: ${response.statusCode}`);
    return next();
  }
  
  try {
    const body = JSON.parse(response.body);
    
    // 验证必需字段
    if (typeof body.total_records !== 'number' || body.total_records < 0) {
      ee.emit('error', 'Invalid total_records in stats response');
    }
    
    if (!body.priority_stats || typeof body.priority_stats !== 'object') {
      ee.emit('error', 'Invalid priority_stats in stats response');
    }
    
    if (typeof body.recent_24h_count !== 'number' || body.recent_24h_count < 0) {
      ee.emit('error', 'Invalid recent_24h_count in stats response');
    }
    
  } catch (error) {
    ee.emit('error', `Failed to parse stats response: ${error.message}`);
  }
  
  return next();
}

// 日志记录
function logRequest(requestParams, response, context, ee, next) {
  const timestamp = new Date().toISOString();
  const url = requestParams.url || 'unknown';
  const method = requestParams.method || 'unknown';
  const status = response.statusCode || 'unknown';
  const duration = response.timings ? response.timings.response : 'unknown';
  
  console.log(`[${timestamp}] ${method} ${url} - ${status} - ${duration}ms`);
  
  // 记录载荷大小信息
  if (context.vars.sensorData && context.vars.sensorData.data) {
    const payloadSize = Buffer.from(context.vars.sensorData.data, 'base64').length;
    console.log(`  Payload size: ${payloadSize} bytes`);
  }
  
  return next();
}

// 性能监控
function trackPerformance(requestParams, response, context, ee, next) {
  const duration = response.timings ? response.timings.response : 0;
  
  // 记录慢请求
  if (duration > 1000) {
    ee.emit('error', `Slow request detected: ${duration}ms for ${requestParams.url}`);
  }
  
  // 记录错误
  if (response.statusCode >= 400) {
    ee.emit('error', `HTTP error: ${response.statusCode} for ${requestParams.url}`);
  }
  
  return next();
}

// 导出所有函数
module.exports = {
  generateSensorData,
  generateSensorRWData,
  generateBatchData,
  validateSensorDataResponse,
  validateSensorRWResponse,
  validateBatchResponse,
  validateStatsResponse,
  logRequest,
  trackPerformance
}; 