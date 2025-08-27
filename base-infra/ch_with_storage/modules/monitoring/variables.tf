###############################################################################
# ClickHouse External Monitoring Module Variables
# Homework #14: External services only (Prometheus + Grafana + Exporter)
###############################################################################

variable "project_name" {
  description = "Name of the project for labeling resources"
  type        = string
  default     = "clickhouse-engineering-course"
}

variable "clickhouse_network_name" {
  description = "Name of the existing ClickHouse network"
  type        = string
}

variable "clickhouse_network_id" {
  description = "ID of the existing ClickHouse network"
  type        = string
}

variable "clickhouse_uri" {
  description = "ClickHouse connection URI"
  type        = string
}

variable "clickhouse_user" {
  description = "ClickHouse username"
  type        = string
}

variable "clickhouse_password" {
  description = "ClickHouse password"
  type        = string
  sensitive   = true
}

variable "clickhouse_hosts" {
  description = "List of ClickHouse hosts for Prometheus scraping"
  type        = list(string)
  default     = ["clickhouse-01:8123", "clickhouse-02:8123", "clickhouse-03:8123", "clickhouse-04:8123"]
}

# --- Grafana Configuration ---
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_admin_username" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_email" {
  description = "Grafana admin email"
  type        = string
  default     = "admin@monitoring.local"
}

variable "grafana_local_users" {
  description = "List of local Grafana users to create"
  type = list(object({
    username   = string
    password   = string
    first_name = string
    last_name  = string
    email      = string
    role       = string # Admin, Editor, Viewer
  }))
  default = []
}

variable "super_user_name" {
  description = "Super user name (used as fallback for grafana admin if grafana_admin_username not set)"
  type        = string
  default     = null
}

variable "super_user_password" {
  description = "Super user password (used as fallback for grafana admin if grafana_admin_password not set)"
  type        = string
  default     = null
  sensitive   = true
}

# --- Port Configuration ---
variable "prometheus_port" {
  description = "Prometheus external port"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "Grafana external port (changed from 3000 due to Metabase conflict)"
  type        = number
  default     = 3001
}

variable "clickhouse_exporter_port" {
  description = "ClickHouse exporter external port"
  type        = number
  default     = 9116
}

variable "clickhouse_base_path" {
  description = "Базовый путь для данных и конфигураций ClickHouse."
  type        = string
}
