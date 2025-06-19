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

variable "enable_eudf" {
  description = "Флаг для включения/отключения шага с копированием executable UDF конфигов и самих функций"
  type        = bool
  default     = true
}
variable "enable_dictionaries" {
  description = "Флаг для включения/отключения шага с копированием XML-конфигов словарей и их данных"
  type        = bool
  default     = false
}