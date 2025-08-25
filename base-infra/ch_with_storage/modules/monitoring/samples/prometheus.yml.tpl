# Prometheus Configuration for ClickHouse Monitoring
# Template file - variables will be substituted by Terraform

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'clickhouse-dwh-test'
    environment: 'homework-14'

# Alertmanager configuration (optional)
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets:
#           # - alertmanager:9093

# Load rules once and periodically evaluate them
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# Scrape configuration
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 30s
    metrics_path: /metrics

  # ClickHouse metrics via dedicated exporter
  - job_name: 'clickhouse-exporter'
    static_configs:
      - targets: ['clickhouse-exporter:9116']
    scrape_interval: 30s
    scrape_timeout: 10s
    metrics_path: /metrics
    params:
      format: ['prometheus']

  # ClickHouse internal metrics endpoint (enabled via config.d/prometheus.xml)
  - job_name: 'clickhouse-internal'
    static_configs:
      - targets: ${jsonencode([for host in clickhouse_hosts : replace(host, ":8123", ":9363")])}
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s
    # ClickHouse internal Prometheus endpoint on port 9363

  # ClickHouse system metrics via custom endpoint
  - job_name: 'clickhouse-system'
    static_configs:
      - targets: ${jsonencode(clickhouse_hosts)}
    metrics_path: /
    scrape_interval: 60s
    scrape_timeout: 15s
    params:
      query: ['SELECT metric, value FROM system.asynchronous_metrics FORMAT Prometheus']
    # Note: This requires custom configuration in ClickHouse

  # Grafana self-monitoring
  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
    metrics_path: /metrics
    scrape_interval: 30s

