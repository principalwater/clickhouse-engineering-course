#!/bin/bash

set -e

DATA_DIR="data"
DATASET_SUBDIR="menusdata_nypl"
DATA_DIR="$DATA_DIR/$DATASET_SUBDIR"
DATASET_URL="https://s3.amazonaws.com/menusdata.nypl.org/gzips/2021_08_01_07_01_17_data.tgz"
ARCHIVE_NAME="2021_08_01_07_01_17_data.tgz"
CSV_FILES=("Dish.csv" "Menu.csv" "MenuItem.csv" "MenuPage.csv")
CONTAINER="clickhouse-01"
CONTAINER_DIR="/var/lib/clickhouse/user_files/menusdata_nypl_dataset"

echo "1. Создаём директорию $DATA_DIR и скачиваем датасет..."
mkdir -p "$DATA_DIR" || { echo "Ошибка создания директории $DATA_DIR"; exit 1; }
cd "$DATA_DIR"

if [ ! -f "$ARCHIVE_NAME" ]; then
  wget "$DATASET_URL" || { echo "Ошибка загрузки архива $DATA_DIR/$ARCHIVE_NAME"; exit 1; }
else
  echo "Файл $DATA_DIR/$ARCHIVE_NAME уже существует, пропускаем скачивание."
fi

echo "2. Распаковываем архив..."
tar xvf "$ARCHIVE_NAME" || { echo "Ошибка распаковки архива $DATA_DIR/$ARCHIVE_NAME"; exit 1; }

for CSV_FILE in "${CSV_FILES[@]}"; do
  if [ ! -f "$CSV_FILE" ]; then
    echo "Не найден файл $DATA_DIR/$CSV_FILE после распаковки!"
    exit 1
  fi
done

cd ../..

echo "3. Копируем CSV файлы в контейнер ClickHouse ($CONTAINER)..."
docker exec -i "$CONTAINER" mkdir -p "$CONTAINER_DIR" || { echo "Ошибка создания директории $CONTAINER_DIR в контейнере"; exit 1; }
for CSV_FILE in "${CSV_FILES[@]}"; do
  docker cp "$DATA_DIR/$CSV_FILE" "$CONTAINER:$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка копирования файла $DATA_DIR/$CSV_FILE в контейнер"; exit 1; }
  docker exec -i "$CONTAINER" chown clickhouse:clickhouse "$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка установки прав на файл в контейнере"; exit 1; }
done

echo "✅ Датасет успешно загружен и готов к использованию!"

# --- Автоматическая загрузка CSV файлов во все контейнеры ClickHouse ---
echo "4. Проверяем переменные окружения TF_VAR_super_user_name и TF_VAR_super_user_password..."
if [ -z "$TF_VAR_super_user_name" ] || [ -z "$TF_VAR_super_user_password" ]; then
  echo "❌ Переменные окружения TF_VAR_super_user_name и/или TF_VAR_super_user_password не заданы!"
  exit 1
fi
CH_USER="$TF_VAR_super_user_name"
CH_PASS="$TF_VAR_super_user_password"

echo "5. Ищем все контейнеры ClickHouse в кластере (исключая keeper)..."
CLICKHOUSE_CONTAINERS=$(docker ps --format '{{.Names}}' | grep -E '^clickhouse-[0-9]+$' || true)
if [ -z "$CLICKHOUSE_CONTAINERS" ]; then
  echo "❌ Контейнеры ClickHouse не найдены!"
  exit 1
fi
echo "Найдены контейнеры: $CLICKHOUSE_CONTAINERS"

for CH_CONT in $CLICKHOUSE_CONTAINERS; do
  echo "----"
  echo "Обработка контейнера $CH_CONT"
  # Вычисляем номер ноды из имени контейнера
  NODE_NUM=$(echo "$CH_CONT" | grep -oE '[0-9]+')
  # По умолчанию используем стандартные порты, если переменная не задана
  if [ -z "$USE_STANDARD_PORTS" ] || [ "$USE_STANDARD_PORTS" = "true" ]; then
    PORT=9000
  else
    PORT=$((9000 + NODE_NUM - 1))
  fi
  echo "  Используем порт $PORT для clickhouse-client"

  echo "  Создаём директорию $CONTAINER_DIR в контейнере..."
  docker exec -i "$CH_CONT" mkdir -p "$CONTAINER_DIR" || { echo "Ошибка создания директории в $CH_CONT"; exit 1; }
  for CSV_FILE in "${CSV_FILES[@]}"; do
    echo "  Копируем $DATA_DIR/$CSV_FILE в $CH_CONT:$CONTAINER_DIR/$CSV_FILE ..."
    docker cp "$DATA_DIR/$CSV_FILE" "$CH_CONT:$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка копирования файла в $CH_CONT"; exit 1; }
    echo "  Устанавливаем права на файл в $CH_CONT..."
    docker exec -i "$CH_CONT" chown clickhouse:clickhouse "$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка установки прав на файл в $CH_CONT"; exit 1; }
  done
  echo "  Загружаем данные из CSV файлов в ClickHouse через clickhouse-client..."
  for CSV_FILE in "${CSV_FILES[@]}"; do
    RAW_NAME=$(basename "$CSV_FILE" .csv)
    TABLE_NAME=$(echo "$RAW_NAME" | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
    docker exec -i "$CH_CONT" bash -c \
      "clickhouse-client --user '$CH_USER' --password '$CH_PASS' --port $PORT --query \"
        INSERT INTO otus_default.$TABLE_NAME FORMAT CSVWithNames
      \" < '$CONTAINER_DIR/$CSV_FILE'" \
      && echo "  ✅ Данные из $CSV_FILE загружены в $CH_CONT" \
      || { echo "Ошибка загрузки данных из $CSV_FILE в $CH_CONT"; exit 1; }
  done
done
echo "✅ Загрузка CSV файлов завершена во всех контейнерах ClickHouse."
