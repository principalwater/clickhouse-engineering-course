#!/bin/bash

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
# shellcheck source=../../base-infra/ch_with_storage/env/clickhouse.env
source "${SCRIPT_DIR}/../../base-infra/ch_with_storage/env/clickhouse.env"

# Variables
CLICKHOUSE_NODE="clickhouse-01"
CLICKHOUSE_USER=${CH_USER:-default}
CLICKHOUSE_PASSWORD=${CH_PASSWORD:-}
OUTPUT_FILE="${SCRIPT_DIR}/../../materials/hw14_monitoring-metrics-logging/star_task_submission.md"

# Functions
function get_config_section() {
    local section=$1
    docker exec $CLICKHOUSE_NODE cat /etc/clickhouse-server/config.d/config.xml | sed -n "/<${section}>/,/<\/${section}>/p" | sed "s/$CLICKHOUSE_PASSWORD/MASKED_PASSWORD/g; s/$CLICKHOUSE_USER/MASKED_USER/g"
}

function get_keeper_config() {
    docker exec $CLICKHOUSE_NODE cat /etc/clickhouse-server/config.d/config.xml | sed -n '/<zookeeper>/,/<\/zookeeper>/p'
}

# Generate report
cat > $OUTPUT_FILE << EOF
# Задание со звездочкой: Система репликации логов
# Секции конфигурации и команды CREATE TABLE

## 1. Engine=Null таблица для приема логов

\`\`\`sql
$(docker exec $CLICKHOUSE_NODE clickhouse-client -u $CLICKHOUSE_USER --password "$CLICKHOUSE_PASSWORD" -q "SHOW CREATE TABLE otus_monitoring.logs_input")
\`\`\`

## 2. Реплицируемая таблица для хранения логов

\`\`\`sql
$(docker exec $CLICKHOUSE_NODE clickhouse-client -u $CLICKHOUSE_USER --password "$CLICKHOUSE_PASSWORD" -q "SHOW CREATE TABLE otus_monitoring.logs_storage")
\`\`\`

## 3. Материализованное представление (MV)

\`\`\`sql
$(docker exec $CLICKHOUSE_NODE clickhouse-client -u $CLICKHOUSE_USER --password "$CLICKHOUSE_PASSWORD" -q "SHOW CREATE TABLE otus_monitoring.logs_mv")
\`\`\`

## 4. Distributed таблица

\`\`\`sql
$(docker exec $CLICKHOUSE_NODE clickhouse-client -u $CLICKHOUSE_USER --password "$CLICKHOUSE_PASSWORD" -q "SHOW CREATE TABLE otus_monitoring.logs_distributed")
\`\`\`

## 5. Конфигурация кластера (XML секции из clickhouse-01)

### remote_servers секция:
\`\`\`xml
$(get_config_section "remote_servers")
\`\`\`

### macros секция:
\`\`\`xml
$(get_config_section "macros")
\`\`\`

### keeper секция:
\`\`\`xml
$(get_keeper_config)
\`\`\`

## 6. Результат проверки репликации

\`\`\`
$(docker exec $CLICKHOUSE_NODE clickhouse-client -u $CLICKHOUSE_USER --password "$CLICKHOUSE_PASSWORD" -q "SELECT replica_name, replica_shard, replica_num, count() FROM otus_monitoring.logs_distributed GROUP BY replica_name, replica_shard, replica_num ORDER BY replica_shard, replica_num")
\`\`\`
EOF

echo "Отчет сгенерирован в $OUTPUT_FILE"
