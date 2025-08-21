output "clickhouse_http_port" {
  description = "HTTP порт для доступа к ClickHouse"
  value       = module.clickhouse_cluster.clickhouse_http_port
}

output "clickhouse_tcp_port" {
  description = "TCP порт для доступа к ClickHouse"  
  value       = module.clickhouse_cluster.clickhouse_tcp_port
}

output "cluster_name" {
  description = "Имя кластера ClickHouse"
  value       = module.clickhouse_cluster.cluster_name
}

output "clickhouse_nodes" {
  description = "Список нод ClickHouse"
  value       = module.clickhouse_cluster.clickhouse_nodes
}

output "local_minio_port" {
  description = "Порт локального MinIO (если используется)"
  value       = module.clickhouse_cluster.local_minio_port
}

output "remote_minio_endpoint" {
  description = "Endpoint удаленного MinIO для backup"
  value       = module.clickhouse_cluster.remote_minio_endpoint
}

output "bucket_backup" {
  description = "Имя бакета для backup"
  value       = module.clickhouse_cluster.bucket_backup
}

output "bucket_storage" {
  description = "Имя бакета для storage (если используется s3_ssd)"
  value       = module.clickhouse_cluster.bucket_storage
}

output "storage_type" {
  description = "Текущий тип хранилища"
  value       = var.storage_type
}

output "enable_remote_backup" {
  description = "Статус удаленного backup"
  value       = var.enable_remote_backup
}