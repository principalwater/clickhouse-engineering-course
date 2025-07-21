# Переменная clickhouse_base_path с дефолтным значением
variable "clickhouse_base_path" {
  description = "Базовый путь для volume ClickHouse"
  type        = string
  default     = "../../base-infra/clickhouse/volumes"
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
  default     = "24.5.1.1198"
}

variable "chk_version" {
  description = "ClickHouse keeper version"
  type        = string
  default     = "24.5.1.1198-alpine"
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

# Переменная для управления развертыванием новых реплик
variable "deploy_new_replicas" {
  description = "Если true, разворачивает дополнительные реплики ClickHouse (ноды 05 и 06)."
  type        = bool
  default     = false
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

variable "cluster_topology" {
  description = "Выбор топологии кластера. Варианты: '2s_2r' (2 шарда, 2 реплики), '4s_1r' (4 шарда, 1 реплика)."
  type        = string
  default     = "2s_2r"
}
