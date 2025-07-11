package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"
)

// PayloadData 负载数据结构
type PayloadData struct {
	Load      []int     `json:"load"`
	Timestamp string    `json:"timestamp"`
	Size      int       `json:"size"`
	Random    string    `json:"random"`
	Sequence  []float64 `json:"sequence"`
	Metadata  string    `json:"metadata"`
}

// GenerateRandomPayload 生成指定大小的随机负载数据
func GenerateRandomPayload(targetSize int) string {
	if targetSize <= 0 {
		targetSize = 1024 // 默认1KB
	}

	// 限制最大大小为64KB（TEXT字段限制）
	if targetSize > 65535 {
		targetSize = 65535
	}

	payload := PayloadData{
		Load:      generateRandomInts(50), // 50个随机整数
		Timestamp: time.Now().Format(time.RFC3339),
		Size:      targetSize,
		Random:    generateRandomString(200), // 200字符的随机字符串
		Sequence:  generateSequence(30),      // 30个数值序列
		Metadata:  generateMetadata(),
	}

	// 序列化为JSON
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return generateFallbackPayload(targetSize)
	}

	// 如果JSON太小，用重复数据填充
	currentSize := len(jsonData)
	if currentSize < targetSize {
		padding := generatePadding(targetSize - currentSize)
		payload.Metadata += padding

		// 重新序列化
		jsonData, err = json.Marshal(payload)
		if err != nil {
			return generateFallbackPayload(targetSize)
		}
	}

	// Base64编码以确保数据安全传输
	return base64.StdEncoding.EncodeToString(jsonData)
}

// generateRandomInts 生成随机整数数组
func generateRandomInts(count int) []int {
	result := make([]int, count)
	bytes := make([]byte, count*4)
	rand.Read(bytes)

	for i := 0; i < count; i++ {
		result[i] = int(bytes[i*4])<<24 | int(bytes[i*4+1])<<16 | int(bytes[i*4+2])<<8 | int(bytes[i*4+3])
		if result[i] < 0 {
			result[i] = -result[i]
		}
		result[i] = result[i] % 10000 // 限制在合理范围内
	}

	return result
}

// generateRandomString 生成随机字符串
func generateRandomString(length int) string {
	bytes := make([]byte, length)
	rand.Read(bytes)
	return base64.URLEncoding.EncodeToString(bytes)[:length]
}

// generateSequence 生成数值序列
func generateSequence(count int) []float64 {
	result := make([]float64, count)
	bytes := make([]byte, 8)

	for i := 0; i < count; i++ {
		rand.Read(bytes)
		// 生成0-1000之间的浮点数
		value := float64(int(bytes[0])<<8|int(bytes[1])) / 655.35
		result[i] = math.Round(value*100) / 100 // 保留2位小数
	}

	return result
}

// generateMetadata 生成元数据
func generateMetadata() string {
	return fmt.Sprintf("generated_at_%d_device_simulation_data_for_load_testing", time.Now().Unix())
}

// generatePadding 生成填充数据
func generatePadding(size int) string {
	if size <= 0 {
		return ""
	}

	// 使用重复字符串填充
	pattern := "_LOAD_TEST_PADDING_DATA_"
	patternLen := len(pattern)

	if size <= patternLen {
		return pattern[:size]
	}

	// 计算需要重复多少次
	repeats := size / patternLen
	remainder := size % patternLen

	result := strings.Repeat(pattern, repeats)
	if remainder > 0 {
		result += pattern[:remainder]
	}

	return result
}

// generateFallbackPayload 生成备用负载数据
func generateFallbackPayload(targetSize int) string {
	// 如果JSON序列化失败，生成简单的重复字符串
	pattern := "FALLBACK_LOAD_TEST_DATA_"
	patternLen := len(pattern)

	if targetSize <= patternLen {
		return pattern[:targetSize]
	}

	repeats := targetSize / patternLen
	remainder := targetSize % patternLen

	result := strings.Repeat(pattern, repeats)
	if remainder > 0 {
		result += pattern[:remainder]
	}

	return base64.StdEncoding.EncodeToString([]byte(result))
}

// GetPayloadSizeInBytes 计算payload的字节大小
func GetPayloadSizeInBytes(data string) int {
	decoded, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return len(data) // 如果不是base64，返回原始长度
	}
	return len(decoded)
}

// GenerateSmallPayload 生成小负载（1KB以下）
func GenerateSmallPayload() string {
	return GenerateRandomPayload(512) // 512字节
}

// GenerateMediumPayload 生成中等负载（1-10KB）
func GenerateMediumPayload() string {
	return GenerateRandomPayload(5120) // 5KB
}

// GenerateLargePayload 生成大负载（10KB以上）
func GenerateLargePayload() string {
	return GenerateRandomPayload(20480) // 20KB
}

// GenerateExtraLargePayload 生成超大负载（接近TEXT字段限制）
func GenerateExtraLargePayload() string {
	return GenerateRandomPayload(60000) // 60KB
}

// ValidatePayloadData 验证负载数据
func ValidatePayloadData(data string) bool {
	if data == "" {
		return true // 空数据是有效的
	}

	// 检查是否是有效的base64
	decoded, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return false
	}

	// 检查解码后的大小是否在合理范围内
	if len(decoded) > 65535 {
		return false
	}

	return true
}

// GetPayloadInfo 获取负载数据信息
func GetPayloadInfo(data string) map[string]interface{} {
	info := map[string]interface{}{
		"is_empty":     data == "",
		"raw_size":     len(data),
		"decoded_size": 0,
		"is_valid":     false,
	}

	if data != "" {
		decoded, err := base64.StdEncoding.DecodeString(data)
		if err == nil {
			info["decoded_size"] = len(decoded)
			info["is_valid"] = true

			// 尝试解析JSON
			var payload PayloadData
			if json.Unmarshal(decoded, &payload) == nil {
				info["has_structure"] = true
				info["load_count"] = len(payload.Load)
				info["sequence_count"] = len(payload.Sequence)
				info["target_size"] = payload.Size
			} else {
				info["has_structure"] = false
			}
		}
	} else {
		info["is_valid"] = true
	}

	return info
}
