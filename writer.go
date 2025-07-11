package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
)

// BatchWriter 批量写入器
type BatchWriter struct {
	db           *sql.DB
	batchSize    int
	buffer       []*SensorData
	mutex        sync.Mutex
	ticker       *time.Ticker
	ctx          context.Context
	cancel       context.CancelFunc
	logger       *logrus.Logger
	writeChannel chan *SensorData
}

// NewBatchWriter 创建新的批量写入器
func NewBatchWriter(db *sql.DB, batchSize int, flushInterval time.Duration) *BatchWriter {
	ctx, cancel := context.WithCancel(context.Background())

	bw := &BatchWriter{
		db:           db,
		batchSize:    batchSize,
		buffer:       make([]*SensorData, 0, batchSize),
		ticker:       time.NewTicker(flushInterval),
		ctx:          ctx,
		cancel:       cancel,
		logger:       logrus.New(),
		writeChannel: make(chan *SensorData, batchSize*10),
	}

	// 启动后台处理协程
	go bw.processLoop()

	return bw
}

// Write 写入单条数据
func (bw *BatchWriter) Write(data *SensorData) error {
	select {
	case bw.writeChannel <- data:
		return nil
	case <-time.After(100 * time.Millisecond):
		return fmt.Errorf("write timeout")
	}
}

// WriteBatch 批量写入数据
func (bw *BatchWriter) WriteBatch(dataList []*SensorData) error {
	if len(dataList) == 0 {
		return nil
	}

	// 直接批量插入，不经过缓冲
	return bw.flushBatch(dataList)
}

// processLoop 后台处理循环
func (bw *BatchWriter) processLoop() {
	for {
		select {
		case data := <-bw.writeChannel:
			bw.mutex.Lock()
			bw.buffer = append(bw.buffer, data)

			if len(bw.buffer) >= bw.batchSize {
				buffer := make([]*SensorData, len(bw.buffer))
				copy(buffer, bw.buffer)
				bw.buffer = bw.buffer[:0]
				bw.mutex.Unlock()

				go bw.flushBatch(buffer)
			} else {
				bw.mutex.Unlock()
			}

		case <-bw.ticker.C:
			bw.mutex.Lock()
			if len(bw.buffer) > 0 {
				buffer := make([]*SensorData, len(bw.buffer))
				copy(buffer, bw.buffer)
				bw.buffer = bw.buffer[:0]
				bw.mutex.Unlock()

				go bw.flushBatch(buffer)
			} else {
				bw.mutex.Unlock()
			}

		case <-bw.ctx.Done():
			// 关闭时刷新剩余数据
			bw.mutex.Lock()
			if len(bw.buffer) > 0 {
				bw.flushBatch(bw.buffer)
			}
			bw.mutex.Unlock()
			return
		}
	}
}

// flushBatch 刷新批量数据到数据库
func (bw *BatchWriter) flushBatch(dataList []*SensorData) error {
	if len(dataList) == 0 {
		return nil
	}

	start := time.Now()

	// 使用事务批量插入
	tx, err := bw.db.Begin()
	if err != nil {
		bw.logger.WithError(err).Error("Failed to begin transaction")
		return err
	}
	defer tx.Rollback()

	// 准备语句
	query := `
	INSERT INTO time_series_data (timestamp, device_id, metric_name, value, priority, data)
	VALUES (?, ?, ?, ?, ?, ?)
	`

	stmt, err := tx.Prepare(query)
	if err != nil {
		bw.logger.WithError(err).Error("Failed to prepare statement")
		return err
	}
	defer stmt.Close()

	// 批量执行
	for _, data := range dataList {
		timestamp, err := time.Parse(time.RFC3339, data.Timestamp)
		if err != nil {
			bw.logger.WithError(err).Error("Invalid timestamp format")
			continue
		}

		_, err = stmt.Exec(timestamp, data.DeviceID, data.MetricName, data.Value, data.Priority, data.Data)
		if err != nil {
			bw.logger.WithError(err).Error("Failed to insert data")
			return err
		}
	}

	// 提交事务
	if err := tx.Commit(); err != nil {
		bw.logger.WithError(err).Error("Failed to commit transaction")
		return err
	}

	duration := time.Since(start)
	bw.logger.WithFields(logrus.Fields{
		"batch_size": len(dataList),
		"duration":   duration,
		"qps":        float64(len(dataList)) / duration.Seconds(),
	}).Info("Batch write completed")

	return nil
}

// Close 关闭批量写入器
func (bw *BatchWriter) Close() error {
	bw.cancel()
	bw.ticker.Stop()

	// 等待处理完成
	time.Sleep(100 * time.Millisecond)

	return nil
}

// CompressedWriter 压缩写入器
type CompressedWriter struct {
	db          *sql.DB
	batchWriter *BatchWriter
	compression bool
	logger      *logrus.Logger
}

// NewCompressedWriter 创建压缩写入器
func NewCompressedWriter(db *sql.DB, batchSize int, flushInterval time.Duration, compression bool) *CompressedWriter {
	return &CompressedWriter{
		db:          db,
		batchWriter: NewBatchWriter(db, batchSize, flushInterval),
		compression: compression,
		logger:      logrus.New(),
	}
}

// Write 写入数据（支持压缩）
func (cw *CompressedWriter) Write(data *SensorData) error {
	if cw.compression {
		// 压缩数据
		compressedData := cw.compressData(data)
		return cw.batchWriter.Write(compressedData)
	}

	return cw.batchWriter.Write(data)
}

// compressData 压缩数据
func (cw *CompressedWriter) compressData(data *SensorData) *SensorData {
	// 将数据序列化为JSON
	jsonData, err := json.Marshal(data)
	if err != nil {
		cw.logger.WithError(err).Error("Failed to marshal data")
		return data
	}

	// 压缩JSON数据
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)

	if _, err := gw.Write(jsonData); err != nil {
		cw.logger.WithError(err).Error("Failed to compress data")
		return data
	}

	if err := gw.Close(); err != nil {
		cw.logger.WithError(err).Error("Failed to close gzip writer")
		return data
	}

	// 创建压缩后的数据记录
	compressedData := &SensorData{
		Timestamp:  data.Timestamp,
		DeviceID:   data.DeviceID,
		MetricName: data.MetricName + "_compressed",
		Value:      float64(buf.Len()), // 存储压缩后的大小
		Priority:   data.Priority,
	}

	return compressedData
}

// Close 关闭压缩写入器
func (cw *CompressedWriter) Close() error {
	return cw.batchWriter.Close()
}

// PriorityWriter 优先级写入器
type PriorityWriter struct {
	highPriorityWriter   *BatchWriter
	mediumPriorityWriter *BatchWriter
	lowPriorityWriter    *BatchWriter
	logger               *logrus.Logger
}

// NewPriorityWriter 创建优先级写入器
func NewPriorityWriter(db *sql.DB, batchSize int) *PriorityWriter {
	return &PriorityWriter{
		highPriorityWriter:   NewBatchWriter(db, batchSize/2, 100*time.Millisecond), // 高优先级，小批量，快速刷新
		mediumPriorityWriter: NewBatchWriter(db, batchSize, 500*time.Millisecond),   // 中优先级，标准配置
		lowPriorityWriter:    NewBatchWriter(db, batchSize*2, 2*time.Second),        // 低优先级，大批量，慢速刷新
		logger:               logrus.New(),
	}
}

// Write 根据优先级写入数据
func (pw *PriorityWriter) Write(data *SensorData) error {
	switch data.Priority {
	case 1: // 高优先级
		return pw.highPriorityWriter.Write(data)
	case 2: // 中优先级
		return pw.mediumPriorityWriter.Write(data)
	case 3: // 低优先级
		return pw.lowPriorityWriter.Write(data)
	default:
		return pw.mediumPriorityWriter.Write(data)
	}
}

// WriteBatch 批量写入（按优先级分组）
func (pw *PriorityWriter) WriteBatch(dataList []*SensorData) error {
	// 按优先级分组
	highPriority := make([]*SensorData, 0)
	mediumPriority := make([]*SensorData, 0)
	lowPriority := make([]*SensorData, 0)

	for _, data := range dataList {
		switch data.Priority {
		case 1:
			highPriority = append(highPriority, data)
		case 2:
			mediumPriority = append(mediumPriority, data)
		case 3:
			lowPriority = append(lowPriority, data)
		default:
			mediumPriority = append(mediumPriority, data)
		}
	}

	// 并发写入不同优先级的数据
	var wg sync.WaitGroup
	var errors []error
	var errorMutex sync.Mutex

	if len(highPriority) > 0 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := pw.highPriorityWriter.WriteBatch(highPriority); err != nil {
				errorMutex.Lock()
				errors = append(errors, fmt.Errorf("high priority write error: %w", err))
				errorMutex.Unlock()
			}
		}()
	}

	if len(mediumPriority) > 0 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := pw.mediumPriorityWriter.WriteBatch(mediumPriority); err != nil {
				errorMutex.Lock()
				errors = append(errors, fmt.Errorf("medium priority write error: %w", err))
				errorMutex.Unlock()
			}
		}()
	}

	if len(lowPriority) > 0 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := pw.lowPriorityWriter.WriteBatch(lowPriority); err != nil {
				errorMutex.Lock()
				errors = append(errors, fmt.Errorf("low priority write error: %w", err))
				errorMutex.Unlock()
			}
		}()
	}

	wg.Wait()

	if len(errors) > 0 {
		return fmt.Errorf("batch write errors: %v", errors)
	}

	return nil
}

// Close 关闭优先级写入器
func (pw *PriorityWriter) Close() error {
	var errors []error

	if err := pw.highPriorityWriter.Close(); err != nil {
		errors = append(errors, err)
	}

	if err := pw.mediumPriorityWriter.Close(); err != nil {
		errors = append(errors, err)
	}

	if err := pw.lowPriorityWriter.Close(); err != nil {
		errors = append(errors, err)
	}

	if len(errors) > 0 {
		return fmt.Errorf("close errors: %v", errors)
	}

	return nil
}
