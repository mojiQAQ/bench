package main

import (
	"database/sql"
	"fmt"
	"time"
)

// SensorData 表示传感器数据结构
type SensorData struct {
	Timestamp  string  `json:"timestamp"`
	DeviceID   string  `json:"device_id"`
	MetricName string  `json:"metric_name"`
	Value      float64 `json:"value"`
	Priority   int     `json:"priority"` // 1:高 2:中 3:低
	Data       string  `json:"data"`     // 随机负载数据，用于增大传输量
}

// initDatabase 初始化数据库表结构
func initDatabase(db *sql.DB) error {
	// 创建时序数据表
	createTimeSeriesTable := `
	CREATE TABLE IF NOT EXISTS time_series_data (
		id BIGINT AUTO_INCREMENT PRIMARY KEY,
		timestamp DATETIME(3) NOT NULL,
		device_id VARCHAR(100) NOT NULL,
		metric_name VARCHAR(50) NOT NULL,
		value DOUBLE NOT NULL,
		priority TINYINT NOT NULL DEFAULT 2,
		data TEXT,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		INDEX idx_timestamp (timestamp),
		INDEX idx_device_metric (device_id, metric_name),
		INDEX idx_priority (priority)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
	`

	// 创建设备状态表
	createDeviceStatusTable := `
	CREATE TABLE IF NOT EXISTS device_status (
		device_id VARCHAR(100) PRIMARY KEY,
		current_value DOUBLE NOT NULL,
		last_update DATETIME(3) NOT NULL,
		alert_count INT DEFAULT 0,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
		INDEX idx_last_update (last_update),
		INDEX idx_alert_count (alert_count)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
	`

	// 执行建表语句
	if _, err := db.Exec(createTimeSeriesTable); err != nil {
		return fmt.Errorf("failed to create time_series_data table: %w", err)
	}

	if _, err := db.Exec(createDeviceStatusTable); err != nil {
		return fmt.Errorf("failed to create device_status table: %w", err)
	}

	return nil
}

// DatabaseService 提供数据库操作服务
type DatabaseService struct {
	db *sql.DB
}

func NewDatabaseService(db *sql.DB) *DatabaseService {
	return &DatabaseService{db: db}
}

// InsertSensorData 插入传感器数据
func (ds *DatabaseService) InsertSensorData(data *SensorData) error {
	query := `
	INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data)
	VALUES (?, ?, ?, ?, ?, ?)
	`

	// 解析时间戳
	timestamp, err := time.Parse(time.RFC3339, data.Timestamp)
	if err != nil {
		return fmt.Errorf("invalid timestamp format: %w", err)
	}

	_, err = ds.db.Exec(query, timestamp, data.DeviceID, data.MetricName, data.Value, data.Priority, data.Data)
	return err
}

// InsertSensorDataBatch 批量插入传感器数据
func (ds *DatabaseService) InsertSensorDataBatch(data []*SensorData) error {
	if len(data) == 0 {
		return nil
	}

	tx, err := ds.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	query := `
	INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data)
	VALUES (?, ?, ?, ?, ?, ?)
	`

	stmt, err := tx.Prepare(query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	for _, item := range data {
		timestamp, err := time.Parse(time.RFC3339, item.Timestamp)
		if err != nil {
			return fmt.Errorf("invalid timestamp format: %w", err)
		}

		_, err = stmt.Exec(timestamp, item.DeviceID, item.MetricName, item.Value, item.Priority, item.Data)
		if err != nil {
			return fmt.Errorf("failed to insert data: %w", err)
		}
	}

	return tx.Commit()
}

// GetStats 获取数据库统计信息
func (ds *DatabaseService) GetStats() (map[string]interface{}, error) {
	stats := make(map[string]interface{})

	// 总记录数
	var totalCount int64
	err := ds.db.QueryRow("SELECT COUNT(*) FROM time_series_data").Scan(&totalCount)
	if err != nil {
		return nil, err
	}
	stats["total_records"] = totalCount

	// 按优先级统计
	priorityQuery := `
	SELECT priority, COUNT(*) as count 
	FROM time_series_data 
	GROUP BY priority
	`
	rows, err := ds.db.Query(priorityQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	priorityStats := make(map[int]int64)
	for rows.Next() {
		var priority int
		var count int64
		if err := rows.Scan(&priority, &count); err != nil {
			return nil, err
		}
		priorityStats[priority] = count
	}
	stats["priority_stats"] = priorityStats

	// 最近24小时的数据量
	var recentCount int64
	err = ds.db.QueryRow("SELECT COUNT(*) FROM time_series_data WHERE created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)").Scan(&recentCount)
	if err != nil {
		return nil, err
	}
	stats["recent_24h_count"] = recentCount

	// 设备状态统计
	var deviceCount int64
	err = ds.db.QueryRow("SELECT COUNT(*) FROM device_status").Scan(&deviceCount)
	if err != nil {
		return nil, err
	}
	stats["device_count"] = deviceCount

	// 告警总数
	var totalAlerts int64
	err = ds.db.QueryRow("SELECT SUM(alert_count) FROM device_status").Scan(&totalAlerts)
	if err != nil {
		return nil, err
	}
	stats["total_alerts"] = totalAlerts

	return stats, nil
}
