output "metabase_url" {
  description = "URL для доступа к Metabase"
  value       = var.enable_metabase ? "http://localhost:${var.metabase_port}" : null
}

output "superset_url" {
  description = "URL для доступа к Superset"
  value       = var.enable_superset ? "http://localhost:${var.superset_port}" : null
}

output "metabase_admin_credentials" {
  description = "Учетные данные администратора Metabase"
  value = var.enable_metabase ? {
    username = local.effective_metabase_sa_username
    email    = "${local.effective_metabase_sa_username}@local.com"
    # password не выводим по соображениям безопасности
  } : null
  sensitive = true
}

output "superset_admin_credentials" {
  description = "Учетные данные администратора Superset"
  value = var.enable_superset ? {
    username = local.effective_superset_sa_username
    email    = "${local.effective_superset_sa_username}@local"
    # password не выводим по соображениям безопасности
  } : null
  sensitive = true
}