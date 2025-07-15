package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/mux"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

type Server struct {
	db     *sql.DB
	router *mux.Router
	logger *logrus.Logger
	config *Config
}

// ConfigFile 配置文件结构
type ConfigFile struct {
	Server struct {
		Port string `yaml:"port"`
	} `yaml:"server"`
	Database struct {
		Host         string `yaml:"host"`
		Port         string `yaml:"port"`
		User         string `yaml:"user"`
		Password     string `yaml:"password"`
		Name         string `yaml:"name"`
		MaxOpenConns int    `yaml:"max_open_conns"`
		MaxIdleConns int    `yaml:"max_idle_conns"`
	} `yaml:"database"`
	Logging struct {
		Level  string `yaml:"level"`
		Format string `yaml:"format"`
	} `yaml:"logging"`
	App struct {
		ReadTimeout  string `yaml:"read_timeout"`
		WriteTimeout string `yaml:"write_timeout"`
		IdleTimeout  string `yaml:"idle_timeout"`
	} `yaml:"app"`
}

type Config struct {
	Port         string `yaml:"port"`
	DBHost       string `yaml:"db_host"`
	DBPort       string `yaml:"db_port"`
	DBUser       string `yaml:"db_user"`
	DBPassword   string `yaml:"db_password"`
	DBName       string `yaml:"db_name"`
	MaxOpenConns int    `yaml:"max_open_conns"`
	MaxIdleConns int    `yaml:"max_idle_conns"`
	LogLevel     string `yaml:"log_level"`
	LogFormat    string `yaml:"log_format"`
	ReadTimeout  string `yaml:"read_timeout"`
	WriteTimeout string `yaml:"write_timeout"`
	IdleTimeout  string `yaml:"idle_timeout"`
}

func NewConfig() *Config {
	config := &Config{}

	// 首先尝试读取配置文件
	configPath := getEnv("CONFIG_PATH", "config.yaml")
	if err := loadConfigFromFile(config, configPath); err != nil {
		log.Printf("Warning: Failed to load config file %s: %v", configPath, err)
		log.Println("Falling back to environment variables and defaults")
	}

	// 使用环境变量覆盖配置文件设置（环境变量优先级更高）
	if port := os.Getenv("PORT"); port != "" {
		config.Port = port
	} else if config.Port == "" {
		config.Port = "8080"
	}

	if dbHost := os.Getenv("DB_HOST"); dbHost != "" {
		config.DBHost = dbHost
	} else if config.DBHost == "" {
		config.DBHost = "localhost"
	}

	if dbPort := os.Getenv("DB_PORT"); dbPort != "" {
		config.DBPort = dbPort
	} else if config.DBPort == "" {
		config.DBPort = "3306"
	}

	if dbUser := os.Getenv("DB_USER"); dbUser != "" {
		config.DBUser = dbUser
	} else if config.DBUser == "" {
		config.DBUser = "root"
	}

	if dbPassword := os.Getenv("DB_PASSWORD"); dbPassword != "" {
		config.DBPassword = dbPassword
	} else if config.DBPassword == "" {
		config.DBPassword = ""
	}

	if dbName := os.Getenv("DB_NAME"); dbName != "" {
		config.DBName = dbName
	} else if config.DBName == "" {
		config.DBName = "bench_server"
	}

	// 设置默认值
	if config.MaxOpenConns == 0 {
		config.MaxOpenConns = 25
	}
	if config.MaxIdleConns == 0 {
		config.MaxIdleConns = 5
	}
	if config.LogLevel == "" {
		config.LogLevel = "info"
	}
	if config.LogFormat == "" {
		config.LogFormat = "json"
	}
	if config.ReadTimeout == "" {
		config.ReadTimeout = "15s"
	}
	if config.WriteTimeout == "" {
		config.WriteTimeout = "15s"
	}
	if config.IdleTimeout == "" {
		config.IdleTimeout = "60s"
	}

	return config
}

func loadConfigFromFile(config *Config, configPath string) error {
	// 检查配置文件是否存在
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return fmt.Errorf("config file not found: %s", configPath)
	}

	// 读取配置文件
	data, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("failed to read config file: %w", err)
	}

	// 解析YAML配置文件
	var configFile ConfigFile
	if err := yaml.Unmarshal(data, &configFile); err != nil {
		return fmt.Errorf("failed to parse config file: %w", err)
	}

	// 将解析的配置映射到Config结构体
	config.Port = configFile.Server.Port
	config.DBHost = configFile.Database.Host
	config.DBPort = configFile.Database.Port
	config.DBUser = configFile.Database.User
	config.DBPassword = configFile.Database.Password
	config.DBName = configFile.Database.Name
	config.MaxOpenConns = configFile.Database.MaxOpenConns
	config.MaxIdleConns = configFile.Database.MaxIdleConns
	config.LogLevel = configFile.Logging.Level
	config.LogFormat = configFile.Logging.Format
	config.ReadTimeout = configFile.App.ReadTimeout
	config.WriteTimeout = configFile.App.WriteTimeout
	config.IdleTimeout = configFile.App.IdleTimeout

	return nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func NewServer(config *Config) (*Server, error) {
	// 初始化数据库连接
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&loc=Local",
		config.DBUser, config.DBPassword, config.DBHost, config.DBPort, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// 配置数据库连接池
	db.SetMaxOpenConns(config.MaxOpenConns)
	db.SetMaxIdleConns(config.MaxIdleConns)
	db.SetConnMaxLifetime(time.Hour)

	// 测试数据库连接
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// 初始化表结构
	if err := initDatabase(db); err != nil {
		return nil, fmt.Errorf("failed to initialize database: %w", err)
	}

	// 初始化日志
	logger := logrus.New()

	// 根据配置设置日志格式
	if config.LogFormat == "json" {
		logger.SetFormatter(&logrus.JSONFormatter{})
	} else {
		logger.SetFormatter(&logrus.TextFormatter{})
	}

	// 根据配置设置日志级别
	level, err := logrus.ParseLevel(config.LogLevel)
	if err != nil {
		level = logrus.InfoLevel
	}
	logger.SetLevel(level)

	server := &Server{
		db:     db,
		router: mux.NewRouter(),
		logger: logger,
		config: config,
	}

	server.setupRoutes()
	return server, nil
}

func (s *Server) setupRoutes() {
	// 健康检查
	s.router.HandleFunc("/health", s.healthHandler).Methods("GET")

	// 传感器数据路由
	s.router.HandleFunc("/api/sensor-data", s.sensorDataHandler).Methods("POST")
	s.router.HandleFunc("/api/sensor-rw", s.sensorReadWriteHandler).Methods("POST")
	s.router.HandleFunc("/api/batch-sensor-rw", s.batchSensorReadWriteHandler).Methods("POST")
	s.router.HandleFunc("/api/stats", s.statsHandler).Methods("GET")
	s.router.HandleFunc("/api/get-sensor-data", s.getSensorDataHandler).Methods("POST")

	// 添加中间件
	s.router.Use(s.loggingMiddleware)
	s.router.Use(s.recoveryMiddleware)
}

func (s *Server) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		duration := time.Since(start)

		s.logger.WithFields(logrus.Fields{
			"method":     r.Method,
			"path":       r.URL.Path,
			"duration":   duration,
			"user_agent": r.UserAgent(),
		}).Info("HTTP request")
	})
}

func (s *Server) recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				s.logger.WithField("error", err).Error("Panic recovered")
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(); err != nil {
		http.Error(w, "Database connection failed", http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}

func (s *Server) Start() error {
	srv := &http.Server{
		Addr:         ":" + s.config.Port,
		Handler:      s.router,
		ReadTimeout:  parseDuration(s.config.ReadTimeout),
		WriteTimeout: parseDuration(s.config.WriteTimeout),
		IdleTimeout:  parseDuration(s.config.IdleTimeout),
	}

	// 优雅关闭
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		s.logger.Info("Shutting down server...")
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if err := srv.Shutdown(ctx); err != nil {
			s.logger.WithError(err).Error("Server shutdown error")
		}
	}()

	s.logger.WithField("port", s.config.Port).Info("Starting server")
	return srv.ListenAndServe()
}

func (s *Server) Close() error {
	return s.db.Close()
}

func main() {
	config := NewConfig()

	server, err := NewServer(config)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}
	defer server.Close()

	if err := server.Start(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func parseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		log.Fatalf("Failed to parse duration %s: %v", s, err)
	}
	return d
}
