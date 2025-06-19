variable "clickhouse_base_path" {
  type    = string
  default = "./volumes"
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