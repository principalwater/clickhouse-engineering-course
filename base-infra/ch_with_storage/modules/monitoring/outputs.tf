###############################################################################
# Monitoring Stack Module Outputs
###############################################################################

output "prometheus_url" {
  description = "Prometheus web interface URL"
  value       = "http://localhost:${var.prometheus_port}"
}

output "grafana_url" {
  description = "Grafana web interface URL"
  value       = "http://localhost:${var.grafana_port}"
}

output "clickhouse_exporter_url" {
  description = "ClickHouse exporter metrics URL"
  value       = "http://localhost:${var.clickhouse_exporter_port}/metrics"
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = var.grafana_admin_password
  sensitive   = true
}

output "monitoring_network_name" {
  description = "Name of the monitoring network"
  value       = docker_network.monitoring.name
}

output "prometheus_container_name" {
  description = "Name of the Prometheus container"
  value       = docker_container.prometheus.name
}

output "grafana_container_name" {
  description = "Name of the Grafana container"
  value       = docker_container.grafana.name
}

output "clickhouse_exporter_container_name" {
  description = "Name of the ClickHouse exporter container"
  value       = docker_container.clickhouse_exporter.name
}

output "clickhouse_prometheus_config_paths" {
  description = "Paths to the generated ClickHouse Prometheus configuration files"
  value       = { for k, v in local_file.clickhouse_prometheus_config : k => abspath(v.filename) }
}
