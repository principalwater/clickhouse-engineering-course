variable "clickhouse_base_path" {
  type    = string
  default = "../clickhouse/volumes"
}

variable "memory_limit" {
  type    = number
  default = 12884901888 # 12 * 1024 * 1024 * 1024
}

variable "super_user_name" {
  description = "Основной пользователь ClickHouse (например, your_awesome_user)"
  type        = string
  default     = "su"
}

variable "bi_user_name" {
  description = "BI пользователь ClickHouse (например, bi_user), readonly доступ"
  type        = string
  default     = "bi_user"
}

variable "super_user_password" {
  description = "Пароль super_user (plain, только через env!)"
  type        = string
  sensitive   = true
}

variable "bi_user_password" {
  description = "Пароль bi_user (plain, только через env!)"
  type        = string
  sensitive   = true
}

variable "ch_version" {
  description = "ClickHouse server version"
  type        = string
  default     = "25.5.2-alpine"
}

variable "chk_version" {
  description = "ClickHouse keeper version"
  type        = string
  default     = "25.5.2-alpine"
}

variable "minio_version" {
  description = "MinIO version"
  type        = string
  default     = "RELEASE.2025-07-23T15-54-02Z"
}

variable "ch_uid" {
  description = "UID для clickhouse пользователя в контейнере"
  type        = string
  default     = "101"
}

variable "ch_gid" {
  description = "GID для clickhouse пользователя в контейнере"
  type        = string
  default     = "101"
}

# Переменные для управления портами
variable "use_standard_ports" {
  description = "Использовать стандартные порты для всех нод ClickHouse."
  type        = bool
  default     = true
}

variable "ch_http_port" {
  description = "Стандартный HTTP порт для ClickHouse."
  type        = number
  default     = 8123
}

variable "ch_tcp_port" {
  description = "Стандартный TCP порт для ClickHouse."
  type        = number
  default     = 9000
}

variable "ch_replication_port" {
  description = "Стандартный порт репликации для ClickHouse."
  type        = number
  default     = 9001
}

# MinIO and Backup variables
variable "minio_root_user" {
  description = "Пользователь для доступа к MinIO"
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "Пароль для доступа к MinIO"
  type        = string
  sensitive   = true
}

variable "remote_ssh_user" {
  description = "Имя пользователя для SSH-доступа к удаленному хосту"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Путь к приватному SSH-ключу для доступа к удаленному хосту"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "local_minio_port" {
  description = "Порт для локального MinIO"
  type        = number
  default     = 9010
}

variable "remote_minio_port" {
  description = "Порт для удаленного MinIO (backup)"
  type        = number
  default     = 9000
}

variable "storage_type" {
  description = "Тип основного хранилища для ClickHouse: 'local_ssd', 's3_ssd', или 'local_ssd_backup'"
  type        = string
  default     = "local_ssd"
  validation {
    condition     = contains(["local_ssd", "s3_ssd", "local_ssd_backup"], var.storage_type)
    error_message = "Допустимые значения для storage_type: 'local_ssd', 's3_ssd', или 'local_ssd_backup'."
  }
}

variable "local_minio_path" {
  description = "Путь к данным для локального MinIO на внешнем SSD"
  type        = string
  default     = "/Users/principalwater/docker_volumes/minio/data"
}

variable "remote_minio_path" {
  description = "Путь к данным для удаленного MinIO на Raspberry Pi"
  type        = string
  default     = "/mnt/ssd/minio/data"
}

variable "remote_host_name" {
  description = "Имя хоста для удаленного MinIO"
  type        = string
  default     = "water-rpi.local"
}

variable "bucket_backup" {
  description = "Имя бакета для бэкапов"
  type        = string
  default     = "clickhouse-backups"
}

variable "bucket_storage" {
  description = "Имя бакета для S3 хранилища"
  type        = string
  default     = "clickhouse-storage-bucket"
}

variable "enable_remote_backup" {
  description = "Включить удаленный backup MinIO"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Включить модуль мониторинга (Prometheus, Grafana, etc.)"
  type        = bool
  default     = false
}

# --- Grafana Admin Configuration ---
variable "grafana_admin_username" {
  description = "Имя администратора Grafana (fallback: super_user_name)"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Пароль администратора Grafana (fallback: super_user_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_email" {
  description = "Email администратора Grafana (fallback: super_user_name@monitoring.local)"
  type        = string
  default     = ""
}

variable "clickhouse_hosts" {
  description = "Список хостов ClickHouse для развертывания и мониторинга"
  type        = list(string)
  default     = ["clickhouse-01", "clickhouse-02", "clickhouse-03", "clickhouse-04"]
}

# --- Airflow Configuration ---
variable "enable_airflow" {
  description = "Включить модуль Airflow для ETL процессов"
  type        = bool
  default     = false
}

variable "airflow_version" {
  description = "Версия Docker-образа Apache Airflow"
  type        = string
  default     = "3.0.4"
}

variable "airflow_admin_user" {
  description = "Имя администратора Airflow"
  type        = string
  default     = "admin"
}

variable "airflow_admin_password" {
  description = "Пароль администратора Airflow"
  type        = string
  sensitive   = true
  default     = ""
}

variable "airflow_fernet_key" {
  description = "Fernet key для шифрования в Airflow (32-байтовый base64-encoded ключ)"
  type        = string
  sensitive   = true
  default     = ""
  validation {
    condition     = length(var.airflow_fernet_key) == 44 || var.airflow_fernet_key == ""
    error_message = "Airflow fernet key должен быть 44-символьной base64-encoded строкой или пустым для использования значения по умолчанию."
  }
}

variable "airflow_webserver_secret_key" {
  description = "Secret key для веб-сервера Airflow (32-байтовый base64-encoded ключ)"
  type        = string
  sensitive   = true
  default     = ""
  validation {
    condition     = length(var.airflow_webserver_secret_key) == 44 || var.airflow_webserver_secret_key == ""
    error_message = "Airflow webserver secret key должен быть 44-символьной base64-encoded строкой или пустым для использования значения по умолчанию."
  }
}

variable "airflow_jwt_signing_key" {
  description = "Secret key for Airflow API JWT tokens"
  type        = string
  sensitive   = true
}

# --- PostgreSQL Configuration ---
variable "postgres_version" {
  description = "Версия PostgreSQL для метабазы BI инструментов"
  type        = string
  default     = "16-alpine"
}

variable "postgres_data_path" {
  description = "Путь к директории с данными PostgreSQL"
  type        = string
  default     = "../../volumes/postgres/data"
}

# Airflow PostgreSQL настройки
variable "airflow_pg_user" {
  description = "Имя пользователя PostgreSQL для Airflow"
  type        = string
  default     = "airflow"
}

variable "airflow_pg_password" {
  description = "Пароль пользователя PostgreSQL для Airflow (fallback к super_user_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "airflow_pg_db" {
  description = "Имя базы данных PostgreSQL для Airflow"
  type        = string
  default     = "airflow"
}

# --- Flags для будущих расширений ---
variable "enable_metabase" {
  description = "Включить модуль Metabase (для будущих homework)"
  type        = bool
  default     = false
}

variable "enable_superset" {
  description = "Включить модуль Superset (для будущих homework)"
  type        = bool
  default     = false
}

# Metabase PostgreSQL настройки (для будущего использования)
variable "metabase_pg_user" {
  description = "Имя пользователя PostgreSQL для Metabase"
  type        = string
  default     = "metabase"
}

variable "metabase_pg_password" {
  description = "Пароль пользователя PostgreSQL для Metabase (fallback к super_user_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "metabase_pg_db" {
  description = "Имя базы данных PostgreSQL для Metabase"
  type        = string
  default     = "metabase"
}

# Superset PostgreSQL настройки (для будущего использования)
variable "superset_pg_user" {
  description = "Имя пользователя PostgreSQL для Superset"
  type        = string
  default     = "superset"
}

variable "superset_pg_password" {
  description = "Пароль пользователя PostgreSQL для Superset (fallback к super_user_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "superset_pg_db" {
  description = "Имя базы данных PostgreSQL для Superset"
  type        = string
  default     = "superset"
}

# --- Kafka Configuration ---
variable "enable_kafka" {
  description = "Включить модуль Kafka для интеграции с ClickHouse"
  type        = bool
  default     = false
}

variable "kafka_version" {
  description = "Версия для Docker-образов Confluent Platform (Kafka, Zookeeper)."
  type        = string
  default     = "7.5.0"
}

variable "topic_1min" {
  description = "Название топика для 1-минутных данных."
  type        = string
  default     = "covid_new_cases_1min"
}

variable "topic_5min" {
  description = "Название топика для 5-минутных данных."
  type        = string
  default     = "covid_cumulative_data_5min"
}

variable "kafka_admin_user" {
  description = "Имя пользователя-администратора для Kafka."
  type        = string
  default     = "kafka_admin"
}

variable "kafka_admin_password" {
  description = "Пароль для пользователя-администратора Kafka."
  type        = string
  sensitive   = true
}

variable "kafka_ssl_keystore_password" {
  description = "Пароль для Keystore и Truststore Kafka."
  type        = string
  sensitive   = true
}

variable "secrets_path" {
  description = "Абсолютный путь к директории с секретами для Kafka."
  type        = string
  default     = "../../secrets"
}

variable "enable_kafka_acl" {
  description = "Включить ACL авторизацию в Kafka"
  type        = bool
  default     = false
}

# --- BI Tools Configuration ---
variable "enable_bi_tools" {
  description = "Включить модуль BI инструментов (Metabase + Superset)"
  type        = bool
  default     = false
}

# Superset секретный ключ
variable "superset_secret_key" {
  description = "Secret key для Superset (32-байтовый base64-encoded ключ)"
  type        = string
  sensitive   = true
}


