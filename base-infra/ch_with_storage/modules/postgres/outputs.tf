# --------------------------------------------------------------------------------------------------
# OUTPUT VALUES для модуля PostgreSQL
# --------------------------------------------------------------------------------------------------

# ---- Section: Сетевые выходы ----
output "postgres_network_name" {
  description = "Имя Docker-сети PostgreSQL."
  value       = var.enable_postgres ? docker_network.postgres_network[0].name : ""
}

output "postgres_network_id" {
  description = "ID Docker-сети PostgreSQL."
  value       = var.enable_postgres ? docker_network.postgres_network[0].id : ""
}

# ---- Section: Контейнер PostgreSQL ----
output "postgres_container_name" {
  description = "Имя контейнера PostgreSQL."
  value       = var.enable_postgres ? docker_container.postgres[0].name : ""
}

output "postgres_container_id" {
  description = "ID контейнера PostgreSQL."
  value       = var.enable_postgres ? docker_container.postgres[0].id : ""
}

# ---- Section: Строки подключения ----
output "airflow_connection_string" {
  description = "Строка подключения к PostgreSQL для Airflow."
  value       = var.enable_postgres && var.enable_airflow ? "postgresql://${var.airflow_pg_user}:${local.effective_airflow_pg_password_encoded}@postgres:5432/${var.airflow_pg_db}" : ""
  sensitive   = true
}

output "metabase_connection_string" {
  description = "Строка подключения к PostgreSQL для Metabase."
  value       = var.enable_postgres && var.enable_metabase ? "postgresql://${var.metabase_pg_user}:${local.effective_metabase_pg_password_encoded}@postgres:5432/${var.metabase_pg_db}" : ""
  sensitive   = true
}

output "superset_connection_string" {
  description = "Строка подключения к PostgreSQL для Superset."
  value       = var.enable_postgres && var.enable_superset ? "postgresql://${var.superset_pg_user}:${local.effective_superset_pg_password_encoded}@postgres:5432/${var.superset_pg_db}" : ""
  sensitive   = true
}