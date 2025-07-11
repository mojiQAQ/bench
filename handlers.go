package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// sensorDataHandler 处理传感器数据上报（扩展功能）
func (s *Server) sensorDataHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Only POST method allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var data SensorData
	if err := json.Unmarshal(body, &data); err != nil {
		http.Error(w, "Invalid JSON format", http.StatusBadRequest)
		return
	}

	// 数据验证
	if data.DeviceID == "" || data.MetricName == "" || data.Timestamp == "" {
		http.Error(w, "Missing required fields", http.StatusBadRequest)
		return
	}

	// 验证优先级
	if data.Priority < 1 || data.Priority > 3 {
		data.Priority = 2 // 默认中等优先级
	}

	dbService := NewDatabaseService(s.db)
	if err := dbService.InsertSensorData(&data); err != nil {
		s.logger.WithError(err).Error("Failed to insert sensor data")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": "Data inserted successfully",
	})
}

// sensorReadWriteHandler 处理传感器数据的读写操作（开启事务）
func (s *Server) sensorReadWriteHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Only POST method allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var request struct {
		DeviceID   string  `json:"device_id"`
		MetricName string  `json:"metric_name"`
		NewValue   float64 `json:"new_value"`
		Timestamp  string  `json:"timestamp"`
		Priority   int     `json:"priority"`
		Data       string  `json:"data"`
	}

	if err := json.Unmarshal(body, &request); err != nil {
		http.Error(w, "Invalid JSON format", http.StatusBadRequest)
		return
	}

	// 数据验证
	if request.DeviceID == "" || request.MetricName == "" || request.Timestamp == "" {
		http.Error(w, "Missing required fields", http.StatusBadRequest)
		return
	}

	// 验证优先级
	if request.Priority < 1 || request.Priority > 3 {
		request.Priority = 2
	}

	// 开启事务进行读写操作
	tx, err := s.db.Begin()
	if err != nil {
		s.logger.WithError(err).Error("Failed to begin transaction")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback()

	// 1. 读取当前值
	var currentValue float64
	var currentPriority int
	readQuery := `
		SELECT value, priority 
		FROM time_series_data 
		WHERE device_id = ? AND metric_name = ? 
		ORDER BY timestamp DESC 
		LIMIT 1
	`

	err = tx.QueryRow(readQuery, request.DeviceID, request.MetricName).Scan(&currentValue, &currentPriority)
	if err != nil && err != sql.ErrNoRows {
		s.logger.WithError(err).Error("Failed to read current sensor data")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 2. 计算新值（这里实现一个简单的业务逻辑：如果新值超过阈值，则记录告警）
	var newValue float64
	var alertMessage string

	if request.NewValue > 100.0 { // 假设100是阈值
		newValue = request.NewValue
		alertMessage = fmt.Sprintf("High value alert: %.2f exceeds threshold", request.NewValue)
		// 高优先级告警
		request.Priority = 1
	} else {
		newValue = request.NewValue
	}

	// 3. 插入新记录
	insertQuery := `
		INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data)
		VALUES (?, ?, ?, ?, ?, ?)
	`

	timestamp, err := time.Parse(time.RFC3339, request.Timestamp)
	if err != nil {
		s.logger.WithError(err).Error("Invalid timestamp format")
		http.Error(w, "Invalid timestamp format", http.StatusBadRequest)
		return
	}

	_, err = tx.Exec(insertQuery, timestamp, request.DeviceID, request.MetricName, newValue, request.Priority, request.Data)
	if err != nil {
		s.logger.WithError(err).Error("Failed to insert new sensor data")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 4. 更新设备状态表（如果存在的话，这里创建一个简单的状态记录）
	statusQuery := `
		INSERT INTO device_status (device_id, current_value, last_update, alert_count)
		VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE 
			current_value = VALUES(current_value),
			last_update = VALUES(last_update),
			alert_count = alert_count + VALUES(alert_count)
	`

	alertCount := 0
	if alertMessage != "" {
		alertCount = 1
	}

	_, err = tx.Exec(statusQuery, request.DeviceID, newValue, timestamp, alertCount)
	if err != nil {
		// 如果状态表不存在，忽略错误（这里只是为了演示事务）
		s.logger.WithError(err).Warn("Failed to update device status (table may not exist)")
	}

	// 5. 提交事务
	if err := tx.Commit(); err != nil {
		s.logger.WithError(err).Error("Failed to commit transaction")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 6. 返回结果
	response := map[string]interface{}{
		"status":         "success",
		"device_id":      request.DeviceID,
		"metric_name":    request.MetricName,
		"previous_value": currentValue,
		"new_value":      newValue,
		"priority":       request.Priority,
		"timestamp":      request.Timestamp,
	}

	if alertMessage != "" {
		response["alert"] = alertMessage
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// batchSensorReadWriteHandler 处理批量传感器数据读写操作（开启事务）
func (s *Server) batchSensorReadWriteHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Only POST method allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var request struct {
		Data []struct {
			DeviceID   string  `json:"device_id"`
			MetricName string  `json:"metric_name"`
			NewValue   float64 `json:"new_value"`
			Timestamp  string  `json:"timestamp"`
			Priority   int     `json:"priority"`
			Data       string  `json:"data"`
		} `json:"data"`
	}

	if err := json.Unmarshal(body, &request); err != nil {
		http.Error(w, "Invalid JSON format", http.StatusBadRequest)
		return
	}

	if len(request.Data) == 0 {
		http.Error(w, "Empty data list", http.StatusBadRequest)
		return
	}

	if len(request.Data) > 1000 {
		http.Error(w, "Too many records (max 1000)", http.StatusBadRequest)
		return
	}

	// 开启事务进行批量读写操作
	tx, err := s.db.Begin()
	if err != nil {
		s.logger.WithError(err).Error("Failed to begin transaction")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback()

	var results []map[string]interface{}
	var totalAlerts int

	// 准备语句
	readQuery := `
		SELECT value, priority 
		FROM time_series_data 
		WHERE device_id = ? AND metric_name = ? 
		ORDER BY timestamp DESC 
		LIMIT 1
	`

	insertQuery := `
		INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data)
		VALUES (?, ?, ?, ?, ?, ?)
	`

	statusQuery := `
		INSERT INTO device_status (device_id, current_value, last_update, alert_count)
		VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE 
			current_value = VALUES(current_value),
			last_update = VALUES(last_update),
			alert_count = alert_count + VALUES(alert_count)
	`

	// 批量处理每个传感器数据
	for _, item := range request.Data {
		// 数据验证
		if item.DeviceID == "" || item.MetricName == "" || item.Timestamp == "" {
			continue
		}

		// 验证优先级
		if item.Priority < 1 || item.Priority > 3 {
			item.Priority = 2
		}

		// 1. 读取当前值
		var currentValue float64
		var currentPriority int
		err = tx.QueryRow(readQuery, item.DeviceID, item.MetricName).Scan(&currentValue, &currentPriority)
		if err != nil && err != sql.ErrNoRows {
			s.logger.WithError(err).Error("Failed to read current sensor data")
			continue
		}

		// 2. 计算新值和业务逻辑
		var newValue float64
		var alertMessage string
		var alertCount int

		if item.NewValue > 100.0 { // 阈值检查
			newValue = item.NewValue
			alertMessage = fmt.Sprintf("High value alert: %.2f exceeds threshold", item.NewValue)
			item.Priority = 1
			alertCount = 1
			totalAlerts++
		} else {
			newValue = item.NewValue
		}

		// 3. 插入新记录
		timestamp, err := time.Parse(time.RFC3339, item.Timestamp)
		if err != nil {
			s.logger.WithError(err).Error("Invalid timestamp format")
			continue
		}

		_, err = tx.Exec(insertQuery, timestamp, item.DeviceID, item.MetricName, newValue, item.Priority, item.Data)
		if err != nil {
			s.logger.WithError(err).Error("Failed to insert new sensor data")
			continue
		}

		// 4. 更新设备状态
		_, err = tx.Exec(statusQuery, item.DeviceID, newValue, timestamp, alertCount)
		if err != nil {
			s.logger.WithError(err).Warn("Failed to update device status")
		}

		// 5. 记录结果
		result := map[string]interface{}{
			"device_id":      item.DeviceID,
			"metric_name":    item.MetricName,
			"previous_value": currentValue,
			"new_value":      newValue,
			"priority":       item.Priority,
			"timestamp":      item.Timestamp,
			"status":         "success",
		}

		if alertMessage != "" {
			result["alert"] = alertMessage
		}

		results = append(results, result)
	}

	// 6. 提交事务
	if err := tx.Commit(); err != nil {
		s.logger.WithError(err).Error("Failed to commit transaction")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 7. 返回批量处理结果
	response := map[string]interface{}{
		"status":          "success",
		"total_processed": len(results),
		"total_alerts":    totalAlerts,
		"results":         results,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// statsHandler 处理统计信息请求
func (s *Server) statsHandler(w http.ResponseWriter, r *http.Request) {
	dbService := NewDatabaseService(s.db)
	stats, err := dbService.GetStats()
	if err != nil {
		s.logger.WithError(err).Error("Failed to get stats")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// getSensorDataHandler 处理传感器数据查询请求
func (s *Server) getSensorDataHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Only POST method allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var request struct {
		DeviceID   string `json:"device_id"`
		MetricName string `json:"metric_name,omitempty"`
		StartTime  string `json:"start_time"`
		EndTime    string `json:"end_time"`
		Limit      int    `json:"limit,omitempty"`
		Offset     int    `json:"offset,omitempty"`
	}

	if err := json.Unmarshal(body, &request); err != nil {
		http.Error(w, "Invalid JSON format", http.StatusBadRequest)
		return
	}

	// 数据验证
	if request.DeviceID == "" || request.StartTime == "" || request.EndTime == "" {
		http.Error(w, "Missing required fields: device_id, start_time, end_time", http.StatusBadRequest)
		return
	}

	// 验证时间格式
	startTime, err := time.Parse(time.RFC3339, request.StartTime)
	if err != nil {
		http.Error(w, "Invalid start_time format (RFC3339 required)", http.StatusBadRequest)
		return
	}

	endTime, err := time.Parse(time.RFC3339, request.EndTime)
	if err != nil {
		http.Error(w, "Invalid end_time format (RFC3339 required)", http.StatusBadRequest)
		return
	}

	// 验证时间范围
	if startTime.After(endTime) {
		http.Error(w, "start_time must be before end_time", http.StatusBadRequest)
		return
	}

	// 设置默认值
	if request.Limit <= 0 || request.Limit > 10000 {
		request.Limit = 1000 // 默认限制1000条记录
	}

	if request.Offset < 0 {
		request.Offset = 0
	}

	// 构建查询SQL
	var query string
	var args []interface{}

	if request.MetricName != "" {
		// 查询特定指标
		query = `
			SELECT id, timestamp, device_id, metric_name, value, priority, 
				   SUBSTRING(data, 1, 100) as data_preview, LENGTH(data) as data_length,
				   created_at
			FROM time_series_data 
			WHERE device_id = ? AND metric_name = ? 
			  AND timestamp >= ? AND timestamp <= ?
			ORDER BY timestamp DESC
			LIMIT ? OFFSET ?
		`
		args = []interface{}{request.DeviceID, request.MetricName, startTime, endTime, request.Limit, request.Offset}
	} else {
		// 查询所有指标
		query = `
			SELECT id, timestamp, device_id, metric_name, value, priority, 
				   SUBSTRING(data, 1, 100) as data_preview, LENGTH(data) as data_length,
				   created_at
			FROM time_series_data 
			WHERE device_id = ? 
			  AND timestamp >= ? AND timestamp <= ?
			ORDER BY timestamp DESC
			LIMIT ? OFFSET ?
		`
		args = []interface{}{request.DeviceID, startTime, endTime, request.Limit, request.Offset}
	}

	// 执行查询
	rows, err := s.db.Query(query, args...)
	if err != nil {
		s.logger.WithError(err).Error("Failed to query sensor data")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	// 解析查询结果
	var results []map[string]interface{}
	for rows.Next() {
		var id int64
		var timestamp time.Time
		var deviceID, metricName string
		var value float64
		var priority int
		var dataPreview string
		var dataLength int
		var createdAt time.Time

		err := rows.Scan(&id, &timestamp, &deviceID, &metricName, &value, &priority, &dataPreview, &dataLength, &createdAt)
		if err != nil {
			s.logger.WithError(err).Error("Failed to scan sensor data row")
			continue
		}

		result := map[string]interface{}{
			"id":           id,
			"timestamp":    timestamp.Format(time.RFC3339),
			"device_id":    deviceID,
			"metric_name":  metricName,
			"value":        value,
			"priority":     priority,
			"data_preview": dataPreview,
			"data_length":  dataLength,
			"created_at":   createdAt.Format(time.RFC3339),
		}

		results = append(results, result)
	}

	if err := rows.Err(); err != nil {
		s.logger.WithError(err).Error("Error iterating over sensor data rows")
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 获取总记录数（用于分页）
	var totalCount int64
	var countQuery string
	var countArgs []interface{}

	if request.MetricName != "" {
		countQuery = `
			SELECT COUNT(*) FROM time_series_data 
			WHERE device_id = ? AND metric_name = ? 
			  AND timestamp >= ? AND timestamp <= ?
		`
		countArgs = []interface{}{request.DeviceID, request.MetricName, startTime, endTime}
	} else {
		countQuery = `
			SELECT COUNT(*) FROM time_series_data 
			WHERE device_id = ? 
			  AND timestamp >= ? AND timestamp <= ?
		`
		countArgs = []interface{}{request.DeviceID, startTime, endTime}
	}

	err = s.db.QueryRow(countQuery, countArgs...).Scan(&totalCount)
	if err != nil {
		s.logger.WithError(err).Warn("Failed to get total count")
		totalCount = int64(len(results)) // 降级处理
	}

	// 构建响应
	response := map[string]interface{}{
		"status":      "success",
		"device_id":   request.DeviceID,
		"metric_name": request.MetricName,
		"start_time":  request.StartTime,
		"end_time":    request.EndTime,
		"total_count": totalCount,
		"limit":       request.Limit,
		"offset":      request.Offset,
		"count":       len(results),
		"data":        results,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}
