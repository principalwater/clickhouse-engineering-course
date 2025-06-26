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

# No default - must be set via environment variable or tfvars
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
  description = "Version of Superset Docker image"
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

# No default - must be set via environment variable or tfvars
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

# No default - must be set via environment variable or tfvars
variable "superset_secret_key" {
  description = "Secret key for Superset security"
  type        = string
  sensitive   = true
}

######################################################################
# BI and admin user accounts for Metabase and Superset
#
# - sa_username/sa_password: main admin account for both tools
# - metabase_sa_username/metabase_sa_password: Metabase admin, defaults to sa_*
# - superset_sa_username/superset_sa_password: Superset admin, defaults to sa_*
# - bi_user: main BI user login (default: "bi_user")
# - metabase_bi_username/superset_bi_username: BI usernames for each tool, default to bi_user
# - metabase_bi_password/superset_bi_password: BI user passwords
######################################################################

variable "sa_username" {
  description = "Main admin username for Metabase and Superset"
  type        = string
  default     = "sa_user"
}

# No default - must be set via environment variable or tfvars
variable "sa_password" {
  description = "Main admin password for Metabase and Superset"
  type        = string
  sensitive   = true
}

# Username defaults match generic admin/bi_user patterns. For advanced logic, use locals in main.tf.
variable "metabase_sa_username" {
  description = "Admin username for Metabase (defaults to sa_username)"
  type        = string
  default     = "sa_user"
}

# No default - must be set via environment variable or tfvars
variable "metabase_sa_password" {
  description = "Admin password for Metabase (defaults to sa_password)"
  type        = string
  sensitive   = true
}

variable "superset_sa_username" {
  description = "Admin username for Superset (defaults to sa_username)"
  type        = string
  default     = "sa_user"
}

# No default - must be set via environment variable or tfvars
variable "superset_sa_password" {
  description = "Admin password for Superset (defaults to sa_password)"
  type        = string
  sensitive   = true
}

variable "bi_user" {
  description = "Main BI user login for Metabase and Superset (default: bi_user)"
  type        = string
  default     = "bi_user"
}

variable "metabase_bi_username" {
  description = "BI username for Metabase (defaults to bi_user)"
  type        = string
  default     = "bi_user"
}

# No default - must be set via environment variable or tfvars
variable "metabase_bi_password" {
  description = "BI user password for Metabase"
  type        = string
  sensitive   = true
}

variable "superset_bi_username" {
  description = "BI username for Superset (defaults to bi_user)"
  type        = string
  default     = "bi_user"
}

# No default - must be set via environment variable or tfvars
variable "superset_bi_password" {
  description = "BI user password for Superset"
  type        = string
  sensitive   = true
}

######################################################################
# Local Metabase users for automatic API-based creation
######################################################################
variable "metabase_local_users" {
  description = <<EOT
List of local Metabase users to create at startup (used for automatic API user creation). Each user must be an object with keys: username, password, first_name, last_name.
Users should be provided in locals.tf or main.tf using values from variables above.
Default user list is formed via locals in main.tf for centralized configuration.
EOT
  type = list(object({
    username   = string
    password   = string
    first_name = string
    last_name  = string
  }))
  default = []
}

######################################################################
# Local Superset users for automatic API-based creation
######################################################################
variable "superset_local_users" {
  description = <<EOT
List of local Superset users to create at startup. Each user must be an object with keys: username, password, first_name, last_name, is_admin (bool).
Users should be provided in locals.tf or main.tf using values from variables above.
Default user list is formed via locals in main.tf for centralized configuration.
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