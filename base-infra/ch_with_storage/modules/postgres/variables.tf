# --------------------------------------------------------------------------------------------------
# INPUT VARIABLES для модуля PostgreSQL
# --------------------------------------------------------------------------------------------------

# ---- Section: Основные флаги развертывания ----
variable "enable_postgres" {
  description = "Развернуть PostgreSQL для метабазы BI инструментов."
  type        = bool
  default     = false
}

# ---- Section: Версии ----
variable "postgres_version" {
  description = "Версия PostgreSQL."
  type        = string
  default     = "16-alpine"
}

# ---- Section: PostgreSQL настройки ----
variable "postgres_data_path" {
  description = "Путь к директории с данными PostgreSQL."
  type        = string
  default     = "../../volumes/postgres/data"
}

variable "postgres_superuser_password" {
  description = "Пароль суперпользователя PostgreSQL."
  type        = string
  sensitive   = true
}

# ---- Section: Флаги включения сервисов ----
variable "enable_airflow" {
  description = "Включить инициализацию базы данных для Airflow."
  type        = bool
  default     = false
}

variable "enable_metabase" {
  description = "Включить инициализацию базы данных для Metabase."
  type        = bool
  default     = false
}

variable "enable_superset" {
  description = "Включить инициализацию базы данных для Superset."
  type        = bool
  default     = false
}

# ---- Section: Airflow настройки ----
variable "airflow_pg_user" {
  description = "Имя пользователя PostgreSQL для Airflow."
  type        = string
  default     = "airflow"
}

variable "airflow_pg_password" {
  description = "Пароль пользователя PostgreSQL для Airflow."
  type        = string
  sensitive   = true
  default     = ""
}

variable "airflow_pg_db" {
  description = "Имя базы данных PostgreSQL для Airflow."
  type        = string
  default     = "airflow"
}

# ---- Section: Metabase настройки ----
variable "metabase_pg_user" {
  description = "Имя пользователя PostgreSQL для Metabase."
  type        = string
  default     = "metabase"
}

variable "metabase_pg_password" {
  description = "Пароль пользователя PostgreSQL для Metabase."
  type        = string
  sensitive   = true
  default     = ""
}

variable "metabase_pg_db" {
  description = "Имя базы данных PostgreSQL для Metabase."
  type        = string
  default     = "metabase"
}

# ---- Section: Superset настройки ----
variable "superset_pg_user" {
  description = "Имя пользователя PostgreSQL для Superset."
  type        = string
  default     = "superset"
}

variable "superset_pg_password" {
  description = "Пароль пользователя PostgreSQL для Superset."
  type        = string
  sensitive   = true
  default     = ""
}

variable "superset_pg_db" {
  description = "Имя базы данных PostgreSQL для Superset."
  type        = string
  default     = "superset"
}