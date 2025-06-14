variable "metabase_version" {
  description = "Version of Metabase Docker image"
  type        = string
  default     = "v0.55.3"
}

variable "postgres_version" {
  description = "Version of Postgres Docker image"
  type        = string
  default     = "17.5"
}

variable "pg_user" {
  description = "Username for Postgres (and Metabase app DB)"
  type        = string
  default     = "metabase"
}

variable "pg_password" {
  description = "Password for Postgres/Metabase"
  type        = string
  sensitive   = true
}

variable "pg_db" {
  description = "Database name for Metabase"
  type        = string
  default     = "metabaseappdb"
}

variable "metabase_port" {
  description = "Host port for Metabase UI"
  type        = number
  default     = 3000
}