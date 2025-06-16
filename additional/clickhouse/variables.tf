variable "clickhouse_image_version" {
  description = "Версия образа ClickHouse"
  default     = "25.5.2.47"
}

variable "clickhouse_volumes_path" {
  description = "Путь к каталогу volumes для ClickHouse кластера"
  type        = string
  default     = "../../base-infra/clickhouse/volumes"
}

variable "udf_dir" {
  description = "Каталог с UDF-функциями (.py)"
  type        = string
  default     = "user_scripts"
}