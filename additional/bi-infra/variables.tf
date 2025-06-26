# All variable defaults are constants for Terraform compatibility.
# Cross-variable logic is handled in locals.tf.

# ---- Section: Versions and general parameters ----
variable "postgres_version" {
  description = "Version of Postgres Docker image"
  type        = string
  default     = "17.5"
}

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

variable "superset_version" {
  description = "Version of Superset Docker image"
  type        = string
  default     = "4.1.2"
}

variable "superset_port" {
  description = "Host port for Superset UI"
  type        = number
  default     = 8088
}

# ---- Section: Postgres database variables for Metabase and Superset ----
variable "metabase_pg_user" {
  description = "Username for Metabase DB"
  type        = string
  default     = "metabase"
}

variable "postgres_restore_enabled" {
  description = "Выполнять восстановление (или инициализацию) данных Postgres при пустом каталоге pgdata"
  type        = bool
  default     = true
}

# No default. Must be set via environment variable or tfvars, or fallback to pg_password (see locals.tf).
variable "metabase_pg_password" {
  description = "Password for Metabase DB"
  type        = string
  sensitive   = true
  default     = null
}

variable "superset_pg_user" {
  description = "Username for Superset DB"
  type        = string
  default     = "superset"
}

# No default. Must be set via environment variable or tfvars, or fallback to pg_password (see locals.tf).
variable "superset_pg_password" {
  description = "Password for Superset DB"
  type        = string
  sensitive   = true
  default     = null
}

variable "pg_password" {
  description = "Global Postgres password used as fallback for Metabase and Superset"
  type        = string
  sensitive   = true
}

variable "metabase_pg_db" {
  description = "Database name for Metabase"
  type        = string
  default     = "metabaseappdb"
}

variable "superset_pg_db" {
  description = "Database name for Superset metadata"
  type        = string
  default     = "superset"
}

# ---- Section: Global BI and SA user accounts ----
variable "sa_username" {
  description = "Main admin username for Metabase and Superset (no default, must be set explicitly)"
  type        = string
}

variable "sa_password" {
  description = "Main admin password for Metabase and Superset (no default, must be set explicitly)"
  type        = string
  sensitive   = true
}

variable "bi_user" {
  description = "Main BI user login for Metabase and Superset (default: bi_user)"
  type        = string
  default     = "bi_user"
}

variable "bi_password" {
  description = "Main BI user password for Metabase and Superset (no default, must be set explicitly)"
  type        = string
  sensitive   = true
}

# ---- Section: Metabase settings and users ----
variable "metabase_site_name" {
  description = "Название сайта Metabase для использования в setup wizard (API инициализация)"
  type        = string
  default     = "Metabase"
}

variable "metabase_sa_username" {
  description = "Admin username for Metabase (fallback: sa_username; handled in locals.tf)"
  type        = string
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "metabase_sa_password" {
  description = "Admin password for Metabase (fallback: sa_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "metabase_bi_username" {
  description = "BI username for Metabase (fallback: bi_user; handled in locals.tf)"
  type        = string
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "metabase_bi_password" {
  description = "BI user password for Metabase (fallback: bi_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

# ---- Section: Superset settings and users ----
variable "superset_sa_username" {
  description = "Admin username for Superset (fallback: sa_username; handled in locals.tf)"
  type        = string
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "superset_sa_password" {
  description = "Admin password for Superset (fallback: sa_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "superset_secret_key" {
  description = "Secret key for Superset security (no default, must be set explicitly)"
  type        = string
  sensitive   = true
}

variable "superset_bi_username" {
  description = "BI username for Superset (fallback: bi_user; handled in locals.tf)"
  type        = string
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

variable "superset_bi_password" {
  description = "BI user password for Superset (fallback: bi_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  # Not required at launch: used only in fallback logic (see locals.tf)
  default     = null
}

# ---- Section: Local Metabase users for automatic API-based creation ----
variable "metabase_local_users" {
  description = <<EOT
List of local Metabase users to create at startup (used for automatic API user creation). Each user must be an object with keys: username, password, first_name, last_name.
If not set, will be generated in locals.tf from relevant variables above.
EOT
  type = list(object({
    username   = string
    password   = string
    first_name = string
    last_name  = string
  }))
  default = []
}

# ---- Section: Local Superset users for automatic API-based creation ----
variable "superset_local_users" {
  description = <<EOT
List of local Superset users to create at startup. Each user must be an object with keys: username, password, first_name, last_name, is_admin (bool).
If not set, will be generated in locals.tf from relevant variables above.
EOT
  type = list(object({
    username   = string
    password   = string
    first_name = string
    last_name  = string
    is_admin   = bool
  }))
  default = []
}

variable "enable_metabase" {
  description = "Флаг включения Metabase"
  type        = bool
  default     = true
}

variable "enable_superset" {
  description = "Флаг включения Superset"
  type        = bool
  default     = true
}
# ---- Section: Postgres superuser password ----
variable "postgres_superuser_password" {
  description = "Пароль суперпользователя (postgres) для контейнера Postgres. Используется для административных задач."
  type        = string
  sensitive   = true
  default     = null
}
