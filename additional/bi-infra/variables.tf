# All variable defaults are constants for Terraform compatibility.
# Cross-variable logic is handled in locals.tf.

# ---- Section: Versions and general parameters ----
variable "postgres_version" {
  description = "Postgres Docker image version"
  type        = string
  default     = "17.5"
}

variable "metabase_version" {
  description = "Metabase Docker image version"
  type        = string
  default     = "v0.55.3"
}

variable "metabase_port" {
  description = "Host port for Metabase UI"
  type        = number
  default     = 3000
}

variable "superset_version" {
  description = "Superset Docker image version"
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
  description = "Postgres username for Metabase database"
  type        = string
  default     = "metabase"
}

variable "postgres_restore_enabled" {
  description = "Enable Postgres data restore or initialization when pgdata directory is empty"
  type        = bool
  default     = true
}

variable "metabase_pg_password" {
  description = "Postgres password for Metabase database"
  type        = string
  sensitive   = true
  default     = null
}

variable "superset_pg_user" {
  description = "Postgres username for Superset database"
  type        = string
  default     = "superset"
}

variable "superset_pg_password" {
  description = "Postgres password for Superset database"
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
  description = "Main admin username for Metabase and Superset (must be set explicitly)"
  type        = string
}

variable "sa_password" {
  description = "Main admin password for Metabase and Superset (must be set explicitly)"
  type        = string
  sensitive   = true
}

variable "bi_user" {
  description = "Main BI user login for Metabase and Superset"
  type        = string
  default     = "bi_user"
}

variable "bi_password" {
  description = "Main BI user password for Metabase and Superset (must be set explicitly)"
  type        = string
  sensitive   = true
}

# ---- Section: Metabase settings and users ----
variable "metabase_site_name" {
  description = "Metabase site name for setup wizard (API initialization)"
  type        = string
  default     = "Metabase"
}

variable "metabase_sa_username" {
  description = "Metabase admin username (fallback: sa_username; handled in locals.tf)"
  type        = string
  default     = null
}

variable "metabase_sa_password" {
  description = "Metabase admin password (fallback: sa_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  default     = null
}

variable "metabase_bi_username" {
  description = "Metabase BI username (fallback: bi_user; handled in locals.tf)"
  type        = string
  default     = null
}

variable "metabase_bi_password" {
  description = "Metabase BI user password (fallback: bi_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  default     = null
}

# ---- Section: Superset settings and users ----
variable "superset_sa_username" {
  description = "Superset admin username (fallback: sa_username; handled in locals.tf)"
  type        = string
  default     = null
}

variable "superset_sa_password" {
  description = "Superset admin password (fallback: sa_password; handled in locals.tf)"
  type        = string
  sensitive   = true
  default     = null
}

variable "superset_secret_key" {
  description = "Secret key for Superset security (must be set explicitly)"
  type        = string
  sensitive   = true
}

variable "superset_bi_username" {
  description = "Superset BI username (fallback: bi_user; handled in locals.tf)"
  type        = string
  default     = null
}

variable "superset_bi_password" {
  description = "Superset BI user password (fallback: bi_password; handled in locals.tf)"
  type        = string
  sensitive   = true
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
  description = "Flag to enable Metabase"
  type        = bool
  default     = true
}

variable "enable_superset" {
  description = "Flag to enable Superset"
  type        = bool
  default     = true
}

# ---- Section: Postgres superuser password ----
variable "postgres_superuser_password" {
  description = "Postgres superuser password for administrative tasks in the Postgres container"
  type        = string
  sensitive   = true
  default     = null
}
