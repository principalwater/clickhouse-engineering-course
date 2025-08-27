# --------------------------------------------------------------------------------------------------
# LOCAL VALUES для модуля PostgreSQL
# --------------------------------------------------------------------------------------------------

locals {
  # Пароли с fallback к основному паролю PostgreSQL
  effective_postgres_superuser_password = var.postgres_superuser_password
  effective_airflow_pg_password         = var.airflow_pg_password != "" ? var.airflow_pg_password : var.postgres_superuser_password
  effective_metabase_pg_password        = var.metabase_pg_password != "" ? var.metabase_pg_password : var.postgres_superuser_password
  effective_superset_pg_password        = var.superset_pg_password != "" ? var.superset_pg_password : var.postgres_superuser_password
  
  # URL-кодированные пароли для строк подключения
  effective_airflow_pg_password_encoded  = replace(replace(local.effective_airflow_pg_password, "@", "%40"), ".", "%2E")
  effective_metabase_pg_password_encoded = replace(replace(local.effective_metabase_pg_password, "@", "%40"), ".", "%2E")
  effective_superset_pg_password_encoded = replace(replace(local.effective_superset_pg_password, "@", "%40"), ".", "%2E")
}