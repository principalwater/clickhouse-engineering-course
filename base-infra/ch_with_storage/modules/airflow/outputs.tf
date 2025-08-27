# --------------------------------------------------------------------------------------------------
# OUTPUTS для модуля Airflow
# --------------------------------------------------------------------------------------------------

output "airflow_webserver_url" {
  description = "URL веб-интерфейса Airflow."
  value       = var.deploy_airflow ? "http://localhost:${var.airflow_webserver_port}" : null
}

output "airflow_flower_url" {
  description = "URL мониторинга Celery Flower."
  value       = var.deploy_airflow ? "http://localhost:${var.airflow_flower_port}" : null
}

output "airflow_network_name" {
  description = "Имя Docker-сети Airflow."
  value       = var.deploy_airflow ? docker_network.airflow_network[0].name : null
}

output "airflow_postgres_container_name" {
  description = "Имя контейнера PostgreSQL для Airflow (управляется внешним модулем postgres)."
  value       = null
}

output "airflow_redis_container_name" {
  description = "Имя контейнера Redis для Airflow."
  value       = var.deploy_airflow ? docker_container.redis[0].name : null
}

output "airflow_webserver_container_name" {
  description = "Имя контейнера веб-сервера Airflow."
  value       = var.deploy_airflow ? docker_container.airflow_api_server[0].name : null
}

output "airflow_scheduler_container_name" {
  description = "Имя контейнера планировщика Airflow."
  value       = var.deploy_airflow ? docker_container.airflow_scheduler[0].name : null
}

output "airflow_worker_container_name" {
  description = "Имя контейнера воркера Airflow."
  value       = var.deploy_airflow ? docker_container.airflow_worker[0].name : null
}

output "airflow_dag_processor_container_name" {
  description = "Имя контейнера DAG процессора Airflow."
  value       = var.deploy_airflow ? docker_container.airflow_dag_processor[0].name : null
}

output "airflow_triggerer_container_name" {
  description = "Имя контейнера триггеров Airflow."
  value       = var.deploy_airflow ? docker_container.airflow_triggerer[0].name : null
}

output "airflow_flower_container_name" {
  description = "Имя контейнера Flower для мониторинга Airflow."
  value       = var.deploy_airflow && var.enable_flower ? docker_container.airflow_flower[0].name : null
}

output "airflow_admin_user" {
  description = "Имя пользователя-администратора Airflow."
  value       = var.deploy_airflow ? var.airflow_admin_user : null
}

output "airflow_postgres_connection_string" {
  description = "Строка подключения к PostgreSQL для Airflow (передается из внешнего модуля postgres)."
  value       = var.deploy_airflow ? var.airflow_postgres_connection_string : null
  sensitive   = true
}

output "airflow_redis_connection_string" {
  description = "Строка подключения к Redis для Airflow."
  value       = var.deploy_airflow ? "redis://:@redis:6379/0" : null
}

output "airflow_dags_path" {
  description = "Путь к директории с DAG файлами Airflow."
  value       = var.deploy_airflow ? abspath(var.airflow_dags_path) : null
}

output "airflow_logs_path" {
  description = "Путь к директории с логами Airflow."
  value       = var.deploy_airflow ? abspath(var.airflow_logs_path) : null
}

output "airflow_plugins_path" {
  description = "Путь к директории с плагинами Airflow."
  value       = var.deploy_airflow ? abspath(var.airflow_plugins_path) : null
}

output "airflow_config_path" {
  description = "Путь к директории с конфигурацией Airflow."
  value       = var.deploy_airflow ? abspath(var.airflow_config_path) : null
}
