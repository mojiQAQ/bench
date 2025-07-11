/**
 * K6 负载测试脚本 - 基于OpenAPI规范
 * 测试Bench Server时序数据存储系统的所有API接口
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.1/index.js";

// 测试配置
export let options = {
  stages: [
    // 预热阶段
    { duration: '30s', target: 20 },
    // 正常负载
    { duration: '2m', target: 50 },
    // 高负载
    { duration: '2m', target: 100 },
    // 峰值负载
    { duration: '1m', target: 200 },
    // 降低负载
    { duration: '2m', target: 50 },
    // 冷却阶段
    { duration: '30s', target: 0 },
  ],
  
  // 性能阈值
  thresholds: {
    // 响应时间阈值
    'http_req_duration': [
      'p(50)<100',    // 50% 请求在100ms内
      'p(95)<500',    // 95% 请求在500ms内
      'p(99)<1000',   // 99% 请求在1s内
    ],
    // 错误率阈值
    'http_req_failed': ['rate<0.01'], // 错误率小于1%
    // 吞吐量阈值
    'http_reqs': ['rate>100'], // 每秒至少100个请求
    // 特定检查的成功率
    'checks': ['rate>0.99'], // 检查成功率大于99%
  },
};

// 基础配置
const BASE_URL = 'http://localhost:8080';

// 测试数据
const testData = new SharedArray('testData', function () {
  const factories = ['001', '002', '003', '004', '005'];
  const devices = Array.from({length: 100}, (_, i) => String(i + 1).padStart(3, '0'));
  const metrics = ['temperature', 'pressure', 'humidity', 'vibration', 'voltage', 'current', 'power', 'flow_rate'];
  const priorities = [1, 2, 3];
  
  return {
    factories,
    devices,
    metrics,
    priorities
  };
});

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

function generateTimestamp() {
  const now = new Date();
  const offset = Math.floor(Math.random() * 3600000); // 1小时内随机
  return new Date(now.getTime() - offset).toISOString();
}

function generateDeviceId() {
  const data = testData[0];
  const factory = randomChoice(data.factories);
  const device = randomChoice(data.devices);
  return `factory_${factory}_device_${device}`;
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
  return btoa(jsonStr);
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

function generateSensorData() {
  const data = testData[0];
  
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
  
  return {
    timestamp: generateTimestamp(),
    device_id: generateDeviceId(),
    metric_name: randomChoice(data.metrics),
    value: randomFloat(10, 150),
    priority: randomChoice(data.priorities),
    data: generateRandomPayload(payloadSize)
  };
}

function generateSensorRWData() {
  const data = testData[0];
  const payloadSize = randomInt(1024, 5120); // 1-5KB随机大小
  
  return {
    device_id: generateDeviceId(),
    metric_name: randomChoice(data.metrics),
    new_value: randomFloat(20, 140),
    timestamp: generateTimestamp(),
    priority: randomChoice(data.priorities),
    data: generateRandomPayload(payloadSize)
  };
}

function generateBatchData() {
  const batchSize = randomInt(2, 5);
  const data = [];
  
  for (let i = 0; i < batchSize; i++) {
    // 批量操作中使用较小的负载数据以避免请求过大
    const payloadSize = randomInt(256, 1024); // 256B-1KB
    data.push({
      ...generateSensorRWData(),
      data: generateRandomPayload(payloadSize)
    });
  }
  
  return { data };
}

// 测试场景
export default function() {
  // 生成随机权重来决定执行哪个测试
  const scenario = Math.random();
  
  if (scenario < 0.05) {
    // 5% - 健康检查
    testHealthCheck();
  } else if (scenario < 0.45) {
    // 40% - 传感器数据上报
    testSensorDataUpload();
  } else if (scenario < 0.80) {
    // 35% - 传感器读写操作
    testSensorReadWrite();
  } else if (scenario < 0.95) {
    // 15% - 批量传感器读写
    testBatchSensorReadWrite();
  } else {
    // 5% - 统计查询
    testStatsQuery();
  }
  
  // 随机等待
  sleep(Math.random() * 2);
}

/**
 * 健康检查测试
 */
function testHealthCheck() {
  const response = http.get(`${BASE_URL}/health`);
  
  check(response, {
    'health check status is 200': (r) => r.status === 200,
    'health check response time < 100ms': (r) => r.timings.duration < 100,
    'health check has correct content type': (r) => r.headers['Content-Type'] && r.headers['Content-Type'].includes('application/json'),
    'health check status is healthy': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'healthy';
      } catch (e) {
        return false;
      }
    }
  });
}

/**
 * 传感器数据上报测试
 */
function testSensorDataUpload() {
  const payload = generateSensorData();
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const response = http.post(`${BASE_URL}/api/sensor-data`, JSON.stringify(payload), params);
  
  check(response, {
    'sensor data upload status is 200': (r) => r.status === 200,
    'sensor data upload response time < 200ms': (r) => r.timings.duration < 200,
    'sensor data upload success': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'success';
      } catch (e) {
        return false;
      }
    },
    'sensor data has payload': (r) => {
      return payload.data && payload.data.length > 0;
    }
  });
}

/**
 * 传感器读写操作测试
 */
function testSensorReadWrite() {
  const payload = generateSensorRWData();
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const response = http.post(`${BASE_URL}/api/sensor-rw`, JSON.stringify(payload), params);
  
  check(response, {
    'sensor rw status is 200': (r) => r.status === 200,
    'sensor rw response time < 300ms': (r) => r.timings.duration < 300,
    'sensor rw success': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'success';
      } catch (e) {
        return false;
      }
    },
    'sensor rw has device_id': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.device_id === payload.device_id;
      } catch (e) {
        return false;
      }
    },
    'sensor rw has new_value': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.new_value === payload.new_value;
      } catch (e) {
        return false;
      }
    },
    'sensor rw has payload data': (r) => {
      return payload.data && payload.data.length > 0;
    }
  });
  
  // 检查是否有告警（当值超过100时）
  if (payload.new_value > 100) {
    check(response, {
      'high value alert generated': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.alert && body.alert.includes('High value alert');
        } catch (e) {
          return false;
        }
      },
      'priority set to 1 for high values': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.priority === 1;
        } catch (e) {
          return false;
        }
      }
    });
  }
}

/**
 * 批量传感器读写测试
 */
function testBatchSensorReadWrite() {
  const payload = generateBatchData();
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  const response = http.post(`${BASE_URL}/api/batch-sensor-rw`, JSON.stringify(payload), params);
  
  check(response, {
    'batch sensor rw status is 200': (r) => r.status === 200,
    'batch sensor rw response time < 500ms': (r) => r.timings.duration < 500,
    'batch sensor rw success': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'success';
      } catch (e) {
        return false;
      }
    },
    'batch sensor rw processed count matches': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.total_processed === payload.data.length;
      } catch (e) {
        return false;
      }
    },
    'batch sensor rw has results': (r) => {
      try {
        const body = JSON.parse(r.body);
        return Array.isArray(body.results) && body.results.length === payload.data.length;
      } catch (e) {
        return false;
      }
    },
    'batch data all have payload': (r) => {
      return payload.data.every(item => item.data && item.data.length > 0);
    }
  });
  
  // 验证告警数量
  const highValueCount = payload.data.filter(item => item.new_value > 100).length;
  if (highValueCount > 0) {
    check(response, {
      'batch alert count is correct': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.total_alerts === highValueCount;
        } catch (e) {
          return false;
        }
      }
    });
  }
}

/**
 * 统计查询测试
 */
function testStatsQuery() {
  const response = http.get(`${BASE_URL}/api/stats`);
  
  check(response, {
    'stats query status is 200': (r) => r.status === 200,
    'stats query response time < 200ms': (r) => r.timings.duration < 200,
    'stats query has total_records': (r) => {
      try {
        const body = JSON.parse(r.body);
        return typeof body.total_records === 'number' && body.total_records >= 0;
      } catch (e) {
        return false;
      }
    },
    'stats query has priority_stats': (r) => {
      try {
        const body = JSON.parse(r.body);
        return typeof body.priority_stats === 'object' && body.priority_stats !== null;
      } catch (e) {
        return false;
      }
    },
    'stats query has recent_24h_count': (r) => {
      try {
        const body = JSON.parse(r.body);
        return typeof body.recent_24h_count === 'number' && body.recent_24h_count >= 0;
      } catch (e) {
        return false;
      }
    }
  });
}

/**
 * 自定义报告生成
 */
export function handleSummary(data) {
  return {
    "k6-load-test-report.html": htmlReport(data),
    "k6-load-test-summary.txt": textSummary(data, { indent: " ", enableColors: true }),
    stdout: textSummary(data, { indent: " ", enableColors: true }),
  };
} 