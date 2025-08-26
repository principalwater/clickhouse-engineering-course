#!/bin/bash

# Переходим в нужную директорию и загружаем переменные окружения
cd ../../base-infra/ch_with_storage
source env/clickhouse.env

# Устанавливаем переменные
REPORT_DIR="../../materials/hw15_query-profiling"
REPORT_FILE="$REPORT_DIR/report.md"
DB_NAME="otus_default"
TABLE_NAME="youtube"

# Создаем директорию для отчета, если она не существует
mkdir -p $REPORT_DIR

# Функция для выполнения SQL-запросов с логами
run_query_with_logs() {
    echo "$1" | docker exec -i clickhouse-01 bash -c "clickhouse-client -u '$CH_USER' --password '$CH_PASSWORD' --send_logs_level=trace" 2>&1
}

# Функция для выполнения EXPLAIN-запросов без логов
run_explain_query() {
    echo "$1" | docker exec -i clickhouse-01 bash -c "clickhouse-client -u '$CH_USER' --password '$CH_PASSWORD'" 2>&1
}

# Создаем отчет
cat > $REPORT_FILE << EOF
# Homework #15: Отчет о профилировании запросов

В этом отчете представлены результаты анализа производительности запросов к датасету [YouTube dataset of dislikes](https://clickhouse.com/docs/en/getting-started/example-datasets/youtube-dislikes).

EOF

# Запрос без использования первичного ключа
QUERY_NO_PK="SELECT
    title,
    view_count,
    like_count,
    dislike_count,
    round(like_count / dislike_count, 2) AS ratio
FROM $DB_NAME.$TABLE_NAME
WHERE (title ILIKE '%Tutorial%')
    AND (view_count > 1000)
    AND (dislike_count > 0)
ORDER BY ratio DESC
LIMIT 5;"

EXPLAIN_NO_PK="EXPLAIN
SELECT
    title,
    view_count,
    like_count,
    dislike_count,
    round(like_count / dislike_count, 2) AS ratio
FROM $DB_NAME.$TABLE_NAME
WHERE (title ILIKE '%Tutorial%')
    AND (view_count > 1000)
    AND (dislike_count > 0)
ORDER BY ratio DESC
LIMIT 5;"

# Запрос с использованием первичного ключа
QUERY_WITH_PK="SELECT
    toStartOfMonth(upload_date) AS month,
    count() AS video_count,
    sum(view_count) AS total_views,
    quantileExact(0.5)(like_count) AS median_likes
FROM $DB_NAME.$TABLE_NAME
WHERE (uploader = 'T-Series')
    AND (toYear(upload_date) = 2021)
GROUP BY month
ORDER BY month;"

EXPLAIN_WITH_PK="EXPLAIN
SELECT
    toStartOfMonth(upload_date) AS month,
    count() AS video_count,
    sum(view_count) AS total_views,
    quantileExact(0.5)(like_count) AS median_likes
FROM $DB_NAME.$TABLE_NAME
WHERE (uploader = 'T-Series')
    AND (toYear(upload_date) = 2021)
GROUP BY month
ORDER BY month;"

# Добавляем в отчет
cat >> $REPORT_FILE << EOF

## 1. Запрос без использования первичного ключа

### SQL-запрос
\`\`\`sql
$QUERY_NO_PK
\`\`\`

### Текстовый лог
\`\`\`
EOF
run_query_with_logs "$QUERY_NO_PK" >> $REPORT_FILE
cat >> $REPORT_FILE << EOF
\`\`\`

### EXPLAIN
\`\`\`
EOF
run_explain_query "$EXPLAIN_NO_PK" >> $REPORT_FILE
cat >> $REPORT_FILE << EOF
\`\`\`

## 2. Запрос с использованием первичного ключа

### SQL-запрос
\`\`\`sql
$QUERY_WITH_PK
\`\`\`

### Текстовый лог
\`\`\`
EOF
run_query_with_logs "$QUERY_WITH_PK" >> $REPORT_FILE
cat >> $REPORT_FILE << EOF
\`\`\`

### EXPLAIN
\`\`\`
EOF
run_explain_query "$EXPLAIN_WITH_PK" >> $REPORT_FILE
cat >> $REPORT_FILE << EOF
\`\`\`
EOF

echo "Отчет сгенерирован в файле $REPORT_FILE"
