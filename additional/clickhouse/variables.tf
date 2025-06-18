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

variable "dict_samples_dir" {
  description = "Каталог с примерами файлов для словаря (csv, xml)"
  type        = string
  default     = "samples"
}

variable "enable_copy_udf" {
  description = "Enable copying UDF files"
  type        = bool
  default     = true
}
variable "enable_dictionaries" {
  description = "Enable copying dictionary XML files"
  type        = bool
  default     = false
}

variable "enable_copy_additional_configs" {
  description = "Флаг для включения/отключения шага с копированием дополнительных XML-конфигов (словари и др.)"
  type    = bool
  default = false
}