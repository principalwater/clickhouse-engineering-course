locals {
  # Fallback logic for BI tool Postgres passwords
  effective_metabase_pg_password = coalesce(var.metabase_pg_password, var.super_user_password)
  effective_superset_pg_password = coalesce(var.superset_pg_password, var.super_user_password)

  # Fallback logic for service account (admin) users
  effective_metabase_sa_username = coalesce(var.metabase_sa_username, var.super_user_name)
  effective_metabase_sa_password = coalesce(var.metabase_sa_password, var.super_user_password)
  effective_superset_sa_username = coalesce(var.superset_sa_username, var.super_user_name)
  effective_superset_sa_password = coalesce(var.superset_sa_password, var.super_user_password)

  # Fallback logic for BI users
  effective_metabase_bi_username = coalesce(var.metabase_bi_username, var.bi_user_name)
  effective_metabase_bi_password = coalesce(var.metabase_bi_password, var.bi_user_password)
  effective_superset_bi_username = coalesce(var.superset_bi_username, var.bi_user_name)
  effective_superset_bi_password = coalesce(var.superset_bi_password, var.bi_user_password)

  # Metabase initial user list for API initialization
  metabase_local_users = length(var.metabase_local_users) > 0 ? var.metabase_local_users : [
    {
      username   = local.effective_metabase_sa_username
      password   = local.effective_metabase_sa_password
      first_name = "Super"
      last_name  = "Admin"
      email      = "${local.effective_metabase_sa_username}@local.com"
    },
    {
      username   = local.effective_metabase_bi_username
      password   = local.effective_metabase_bi_password
      first_name = "BI"
      last_name  = "User"
      email      = "${local.effective_metabase_bi_username}@local.com"
    }
  ]

  # Superset initial user list for API initialization
  superset_local_users = length(var.superset_local_users) > 0 ? var.superset_local_users : [
    {
      username   = local.effective_superset_sa_username
      password   = local.effective_superset_sa_password
      first_name = "Super"
      last_name  = "Admin"
      is_admin   = true
    },
    {
      username   = local.effective_superset_bi_username
      password   = local.effective_superset_bi_password
      first_name = "BI"
      last_name  = "User"
      is_admin   = false
    }
  ]

  # Service enable flags
  metabase_enabled = var.enable_metabase
  superset_enabled = var.enable_superset
}