#!/bin/bash

set -e

DATA_DIR="data"
DATASET_SUBDIR="menusdata_nypl"
DATA_DIR="$DATA_DIR/$DATASET_SUBDIR"
DATASET_URL="https://s3.amazonaws.com/menusdata.nypl.org/gzips/2021_08_01_07_01_17_data.tgz"
ARCHIVE_NAME="2021_08_01_07_01_17_data.tgz"
CSV_FILE="Menu.csv"
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

if [ ! -f "$CSV_FILE" ]; then
  echo "Не найден файл $DATA_DIR/$CSV_FILE после распаковки!"
  exit 1
fi

cd ../..

echo "3. Копируем $DATA_DIR/$CSV_FILE в контейнер ClickHouse ($CONTAINER)..."
docker exec -i "$CONTAINER" mkdir -p "$CONTAINER_DIR" || { echo "Ошибка создания директории $CONTAINER_DIR в контейнере"; exit 1; }
docker cp "$DATA_DIR/$CSV_FILE" "$CONTAINER:$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка копирования файла $DATA_DIR/$CSV_FILE в контейнер"; exit 1; }
docker exec -i "$CONTAINER" chown clickhouse:clickhouse "$CONTAINER_DIR/$CSV_FILE" || { echo "Ошибка установки прав на файл в контейнере"; exit 1; }

echo "✅ Датасет успешно загружен и готов к использованию!"