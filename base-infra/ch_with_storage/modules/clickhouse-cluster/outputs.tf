output "clickhouse_http_port" {
  description = "HTTP порт для доступа к ClickHouse"
  value       = var.ch_http_port
}

output "clickhouse_tcp_port" {
  description = "TCP порт для доступа к ClickHouse"  
  value       = var.ch_tcp_port
}

output "cluster_name" {
  description = "Имя кластера ClickHouse"
  value       = local.cluster_name
}

output "clickhouse_nodes" {
  description = "Список нод ClickHouse"
  value       = local.clickhouse_nodes
}

output "local_minio_port" {
  description = "Порт локального MinIO (если используется)"
  value       = var.storage_type == "s3_ssd" ? var.local_minio_port : null
}

output "remote_minio_endpoint" {
  description = "Endpoint удаленного MinIO для backup"
  value       = var.enable_remote_backup ? "http://${var.remote_host_name}:${var.remote_minio_port}" : null
}

output "bucket_backup" {
  description = "Имя бакета для backup"
  value       = var.bucket_backup
}

output "bucket_storage" {
  description = "Имя бакета для storage (если используется s3_ssd)"
  value       = var.storage_type == "s3_ssd" ? var.bucket_storage : null
}