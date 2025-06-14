###############################################################################
# Outputs
# Эти значения выводятся после terraform apply и помогают быстро убедиться,
# что кластер запущен и где к нему подключаться.
###############################################################################

# Список контейнеров ClickHouse (шарды × реплики)
output "clickhouse_nodes" {
  description = "Имена всех ClickHouse-контейнеров, сгенерированных Terraform."
  value       = [for n in local.clickhouse_nodes : n.name]
}

# Список контейнеров ClickHouse Keeper
output "keeper_nodes" {
  description = "Имена всех Keeper-контейнеров."
  value       = [for k in local.keeper_nodes : k.name]
}

# Имя первой (условно «главной») ClickHouse-ноды — удобно для тестового подключения
output "primary_clickhouse_node" {
  description = "Первая ClickHouse-нода из списка (шард 1, реплика 1)."
  value       = local.clickhouse_nodes[0].name
}

# Пример HTTP-эндпоинта для быстрой проверки (подставь свой порт, если менялся)
# Обрати внимание: при использовании network_mode = \"host\" на одном хосте
# несколько ClickHouse-процессов с одинаковым портом конфликтуют.
# Для полноценного multi-node запуска на одной машине нужно задавать разные порты
# или использовать bridge-сеть с порт-маппингом.
output "sample_clickhouse_http_endpoint" {
  description = "HTTP endpoint первой ноды (для clickhouse-client или браузера)."
  value       = "${local.clickhouse_nodes[0].name}:8123"
}

# Формируем список host:port всех Keeper-нод (удобно вставить в zookeeper секцию при необходимости)
output "keeper_endpoints" {
  description = "Список 'host:port' всех Keeper-нод."
  value       = [for k in local.keeper_nodes : "${k.host}:${k.tcp_port}"]
}