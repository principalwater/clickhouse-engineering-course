# Домашнее задание №13: Storage Policy и резервное копирование

---

## Оглавление
- [Описание задания и цели](#описание-задания-и-цели)
- [Архитектура решения и аппаратное обеспечение](#архитектура-решения-и-аппаратное-обеспечение)
- [Часть 1. Предварительные проверки и развертывание](#часть-1-предварительные-проверки-и-развертывание)
- [Часть 2. Сценарий с локальным хранилищем](#часть-2-сценарий-с-локальным-хранилищем)
- [Часть 3. Сценарий с S3-хранилищем](#часть-3-сценарий-с-s3-хранилищем)
- [Часть 4. Анализ альтернативных конфигураций](#часть-4-анализ-альтернативных-конфигураций)
- [Общие выводы по заданию](#общие-выводы-по-заданию)
- [Список источников](#список-источников)

---

## Описание задания и цели
В данном домашнем задании будут рассмотрены механизмы управления хранением данных с помощью `Storage Policy` и обеспечение их сохранности через резервное копирование на S3. Будут реализованы и сравнены два подхода к хранению основных данных: на локальном SSD и на S3-совместимом хранилище.

---

## Архитектура решения и аппаратное обеспечение
Для выполнения задания используется гибридная, полностью автоматизированная архитектура, описанная в модуле [`base-infra/ch_with_backup`](../base-infra/ch_with_backup/README.md).

### Создание бакетов S3 (Production-Ready)

Для обеспечения идемпотентности и надежности, особенно в production-средах, управление жизненным циклом бакетов MinIO вынесено из основного потока Terraform. Используется подход "pre-apply script", который гарантирует, что бакеты существуют до того, как они понадобятся другим ресурсам.

**Механизм:**
1.  **Запуск MinIO:** Terraform сперва разворачивает контейнеры `minio-local-storage` и `minio-remote-backup`.
2.  **Проверка готовности:** Специальные `null_resource` (`wait_for_local_minio` и `wait_for_remote_minio`) ожидают, пока API MinIO не станут доступны.
3.  **Создание бакетов:** После успешного запуска MinIO, `null_resource` "minio_buckets" выполняет команды MinIO Client (`mc`) для создания бакетов.
4.  **Команды `mc`:**
    *   `mc alias set ...`: Конфигурирует доступы к инстансам MinIO.
    *   `mc mb --ignore-existing ...`: Создает бакет, если он не существует.
5.  **Запуск остальных ресурсов:** Только после успешного выполнения команд `mc` и создания бакетов Terraform продолжает развертывание остальных ресурсов, включая ClickHouse.

Этот подход решает классическую проблему в Terraform, когда создание ресурса зависит от другого ресурса, который еще не готов.

**Установка зависимостей:**
Для работы этого механизма необходимо, чтобы на машине, с которой запускается Terraform, был установлен [MinIO Client (mc)](https://min.io/docs/minio/linux/reference/minio-mc.html).

### Аппаратное обеспечение
-   **Хост-машина (`mac-studio-foxes-home.local`):** Mac Studio (M2 Max, 32 ГБ RAM)
-   **Внешний накопитель (локальный S3):** Samsung Portable SSD T7 2 ТБ (Thunderbolt 4)
-   **Удаленный сервер (`water-rpi.local`):** Raspberry Pi 5 (8 ГБ RAM, 512 ГБ NVMe SSD), Debian 12 (Bookworm)

---

## Часть 1. Предварительные проверки и развертывание
Перед началом работы необходимо убедиться в доступности всех компонентов и развернуть базовую инфраструктуру.

1.  **Настройте и проверьте SSH-доступ к Docker:**
    Для того чтобы Terraform мог управлять Docker на удаленном хосте, необходимо обеспечить бесшовное SSH-подключение.
    
    *   **Настройка SSH-клиента (рекомендуется):** Добавьте в ваш файл `~/.ssh/config` запись для удаленного хоста. Это позволит не указывать ключ каждый раз.
        ```
        Host water-rpi.local
          HostName water-rpi.local
          User principalwater
          IdentityFile ~/.ssh/water-rpi
        ```
    *   **Проверка:** После настройки `~/.ssh/config` (или добавления ключа в `ssh-agent`), выполните команду на вашей локальной машине. Она должна выполниться без ошибок и показать список (возможно, пустой) контейнеров на удаленном хосте.
        ```sh
        docker --host ssh://water-rpi.local ps
        ```
    Если команда не работает, убедитесь, что пользователь `principalwater` на `water-rpi.local` состоит в группе `docker`.

2.  **Проверка доступности внешнего SSD (для Сценария 2):**
    Убедитесь, что диск смонтирован и доступен по пути, указанному в `local_minio_path`.
    ```sh
    ls -l /Volumes/t7_ssd
    ```

---

## Часть 2. Сценарий с локальным хранилищем
-   **Данные ClickHouse:** Хранятся на локальном SSD хост-машины (`mac-studio-foxes-home.local`). Это обеспечивает максимальную производительность для "горячих" данных.
-   **Резервные копии:** Сохраняются на удаленный S3 (MinIO на `water-rpi.local`).

### 2.1. Развертывание
Разворачиваем конфигурацию с локальным хранением (`storage_type = "local_ssd"`).
```sh
cd base-infra/ch_with_backup
terraform apply -auto-approve -var="storage_type=local_ssd"
```
*Результат:*

<img src="../screenshots/hw13_storage-policy-backup/01_deploy_local.png" alt="Развертывание Сценария 1" width="800"/>

### 2.2. Создание тестовых данных
```sql
CREATE DATABASE IF NOT EXISTS test_db ON CLUSTER dwh_test;
CREATE TABLE IF NOT EXISTS test_db.sample_table ON CLUSTER dwh_test (id UInt64, data String)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/sample_table/{uuid}', '{replica}') ORDER BY id;
INSERT INTO test_db.sample_table SELECT number, randomString(10) FROM numbers(1000);
```

### 2.3. Создание и выгрузка резервной копии
Будет использована команда `create_remote`, которая атомарно выполняет два действия:
1.  **`create`**: Создает локальную резервную копию на диске, доступном контейнеру `clickhouse-backup`.
2.  **`upload`**: Сразу же выгружает созданную копию в удаленное S3-хранилище.
```bash
# Создаем бэкап с уникальным именем, содержащим дату и время
docker exec clickhouse-backup clickhouse-backup create_remote "backup_local_$(date +%Y%m%d_%H%M%S)"
```
*Результат создания бэкапа:*

<img src="../screenshots/hw13_storage-policy-backup/02_create_backup_local.png" alt="Создание бэкапа для Сценария 1" width="800"/>

### 2.4. Имитация сбоя и восстановление
1.  **Удаляем таблицу:**
    ```bash
    docker exec -i clickhouse-01 clickhouse-client --user ${TF_VAR_super_user_name} --password ${TF_VAR_super_user_password} --query "DROP TABLE IF EXISTS test_db.sample_table ON CLUSTER dwh_test SYNC;"
    ```
2.  **Восстанавливаем из бэкапа:**
    Для восстановления необходимо указать имя последней резервной копии.
    ```bash
    LATEST_BACKUP=$(docker exec clickhouse-backup clickhouse-backup list remote | grep '^backup' | tail -1 | awk '{print $1}')
    docker exec clickhouse-backup clickhouse-backup restore_remote $LATEST_BACKUP
    ```
3.  **Проверяем данные:**
    ```bash
    docker exec -i clickhouse-01 clickhouse-client --user ${TF_VAR_super_user_name} --password ${TF_VAR_super_user_password} --query "SELECT count() FROM test_db.sample_table;"
    ```
*Результат повреждения данных и восстановления из бэкапа:*

<img src="../screenshots/hw13_storage-policy-backup/03_01_drop_local.png" alt="Восстановление в Сценарии 1" width="600"/>

<img src="../screenshots/hw13_storage-policy-backup/03_02_restore_local.png" alt="Восстановление в Сценарии 1" width="800"/>

---

## Часть 3. Сценарий с S3-хранилищем
-   **Данные ClickHouse:** Хранятся на "локальном" S3-хранилище MinIO, которое развернуто на внешнем SSD Samsung T7, подключенном к хост-машине. Этот сценарий демонстрирует разделение `compute` и `storage`.
-   **Резервные копии:** Сохраняются на удаленный S3 (MinIO на `water-rpi.local`).

### 3.1. Переключение и развертывание
Уничтожаем предыдущую конфигурацию и разворачиваем новую.
```sh
cd base-infra/ch_with_backup
terraform destroy -auto-approve
terraform apply -auto-approve -var="storage_type=s3_ssd"
```
*Результат:* <img src="../screenshots/hw13_storage-policy-backup/04_deploy_s3.png" alt="Развертывание Сценария 2" width="600"/>

### 3.2. Создание таблицы с Storage Policy
Создаем таблицу, явно указывая политику `s3_main`, чтобы данные хранились на локальном S3.
```sql
CREATE TABLE test_db.sample_table_s3 ON CLUSTER dwh_test (id UInt64, data String)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/sample_table_s3/{uuid}', '{replica}')
ORDER BY id
SETTINGS storage_policy = 's3_main';
INSERT INTO test_db.sample_table_s3 SELECT number, randomString(10) FROM numbers(1000);
```

### 3.3. Проверка хранения данных
Запрос к `system.parts` покажет, что данные хранятся на диске `s3_cache`.
```sql
SELECT table, disk_name, path FROM system.parts WHERE database = 'test_db' AND table = 'sample_table_s3' LIMIT 5;
```
*Результат:* <img src="../screenshots/hw13_storage-policy-backup/05_check_s3_storage.png" alt="Проверка хранения на S3" width="800"/>

### 3.4. Резервное копирование и восстановление
Процесс полностью аналогичен Сценарию 1.
```bash
docker exec clickhouse-backup clickhouse-backup create_remote "backup_s3_$(date +%Y%m%d_%H%M%S)"
# ... drop table ...
LATEST_BACKUP=$(docker exec clickhouse-backup clickhouse-backup list remote | grep '^backup' | tail -1 | awk '{print $1}')
docker exec clickhouse-backup clickhouse-backup restore_remote $LATEST_BACKUP
```
*Результат:* <img src="../screenshots/hw13_storage-policy-backup/06_backup_restore_s3.png" alt="Бэкап и восстановление в Сценарии 2" width="800"/>

---

## Часть 4. Анализ альтернативных конфигураций
На базе имеющегося оборудования возможны и другие интересные конфигурации:
-   **Hot/Cold Storage:** Можно настроить `Storage Policy`, которая будет хранить "горячие" данные (например, за последний месяц) на быстром локальном SSD, а "холодные" — автоматически перемещать на более медленный, но объемный S3 (внешний SSD или удаленный сервер).
-   **Бэкап на локальный S3:** В случае отсутствия удаленного сервера, можно развернуть MinIO на внешнем SSD и использовать его и для хранения данных, и для бэкапов, разнеся их по разным бакетам.
-   **Полностью удаленное хранилище:** Для максимального разделения `compute` и `storage` можно настроить ClickHouse так, чтобы он хранил все данные, включая метаданные, на удаленном S3. Это усложняет настройку, но дает максимальную гибкость в масштабировании.

---

## Общие выводы по заданию
(Этот раздел будет дополнен позже)

---

## Список источников
- [Официальная документация ClickHouse: Политики хранения данных](https://clickhouse.com/docs/ru/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-multiple-volumes)
- [Репозиторий Altinity/clickhouse-backup](https://github.com/Altinity/clickhouse-backup)
