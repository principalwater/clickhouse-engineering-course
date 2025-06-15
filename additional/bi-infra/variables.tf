variable "postgres_version" {
  description = "Version of Postgres Docker image"
  type        = string
  default     = "17.5"
}

# Metabase integration
variable "metabase_version" {
  description = "Version of Metabase Docker image"
  type        = string
  default     = "v0.55.3"
}

variable "metabase_port" {
  description = "Host port for Metabase UI"
  type        = number
  default     = 3000
}

variable "metabase_pg_user" {
  description = "Username for Metabase DB"
  type        = string
  default     = "metabase"
}

variable "metabase_pg_password" {
  description = "Password for Metabase DB"
  type        = string
  sensitive   = true
}

variable "metabase_pg_db" {
  description = "Database name for Metabase"
  type        = string
  default     = "metabaseappdb"
}

# Apache Superset integration
variable "superset_version" {
  description = "Версия Superset Docker image"
  type        = string
  default     = "4.1.2"
}

variable "superset_port" {
  description = "Host port for Superset UI"
  type        = number
  default     = 8088
}

variable "superset_pg_user" {
  description = "Username for Superset DB"
  type        = string
  default     = "superset"
}

variable "superset_pg_password" {
  description = "Password for Superset DB"
  type        = string
  sensitive   = true
}

variable "superset_pg_db" {
  description = "Database name for Superset metadata"
  type        = string
  default     = "superset"
}

variable "superset_secret_key" {
  description = "Secret key for Superset security"
  type        = string
  sensitive   = true
}

variable "superset_sa_user" {
  description = "Username администратора Superset (опционально)"
  type        = string
  default     = "sa"
}

variable "superset_sa_password" {
  description = "Password администратора Superset"
  type        = string
  sensitive   = true
}

variable "superset_sa_email" {
  description = "E-mail администратора Superset (опционально)"
  type        = string
  default     = "admin@localhost"
}