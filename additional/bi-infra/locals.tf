locals {
  # ---- Fallback logic for passwords (Postgres) ----
  effective_metabase_pg_password = coalesce(var.metabase_pg_password, var.pg_password)
  effective_superset_pg_password = coalesce(var.superset_pg_password, var.pg_password)

  # ---- Fallback logic for admin (SA) users ----
  effective_metabase_sa_username = coalesce(var.metabase_sa_username, var.sa_username)
  effective_metabase_sa_password = coalesce(var.metabase_sa_password, var.sa_password)
  effective_superset_sa_username = coalesce(var.superset_sa_username, var.sa_username)
  effective_superset_sa_password = coalesce(var.superset_sa_password, var.sa_password)

  # ---- Fallback logic for BI users ----
  effective_metabase_bi_username = coalesce(var.metabase_bi_username, var.bi_user)
  effective_metabase_bi_password = coalesce(var.metabase_bi_password, var.bi_password)
  effective_superset_bi_username = coalesce(var.superset_bi_username, var.bi_user)
  effective_superset_bi_password = coalesce(var.superset_bi_password, var.bi_password)

  # ---- Metabase local users for API initialization ----
  metabase_local_users = length(var.metabase_local_users) > 0 ? var.metabase_local_users : [
    {
      username   = local.effective_metabase_sa_username
      password   = local.effective_metabase_sa_password
      first_name = "Super"
      last_name  = "Admin"
    },
    {
      username   = local.effective_metabase_bi_username
      password   = local.effective_metabase_bi_password
      first_name = "BI"
      last_name  = "User"
    }
  ]

  # ---- Superset local users for API initialization ----
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
}