# ClickHouse with Modular Storage (ch_with_storage)

Модульная архитектура ClickHouse кластера с гибким управлением хранилищем и резервным копированием.

## Архитектура

### Модульная структура
- `modules/clickhouse-cluster/` - основной модуль ClickHouse кластера
- Четкое разделение логики через переменные модуля
- Условное создание ресурсов через `count`

### Исправленные проблемы
✅ **Корректная логика MinIO**: Remote backup создается только при `enable_remote_backup = true`  
✅ **Модульная архитектура**: Отделение логики кластера от корневого модуля  
✅ **Гибкое управление**: Переменная `enable_remote_backup` для контроля backup  
✅ **S3BackedMergeTree интеграция**: Полная поддержка разделения storage и compute  
✅ **Стабильность контейнеров**: Устранены crash-петли при инициализации S3 дисков  

## Поддерживаемые режимы

### Storage Types
- `local_ssd` - данные на локальном SSD
- `s3_ssd` - данные на локальном S3 (MinIO)

### Backup Options  
- `enable_remote_backup = true` - удаленный backup на water-rpi.local
- `enable_remote_backup = false` - без удаленного backup

## Использование

### Режим 1: Local SSD + Remote Backup (Рекомендуемый)
```bash
terraform apply -auto-approve \
  -var="storage_type=local_ssd" \
  -var="enable_remote_backup=true"
```

### Режим 2: Local SSD + Local Backup  
```bash
terraform apply -auto-approve \
  -var="storage_type=local_ssd_backup"
```

### Режим 3: S3BackedMergeTree (Разделение Storage и Compute)
```bash
terraform apply -auto-approve \
  -var="storage_type=s3_ssd" \
  -var="enable_remote_backup=false"
```

✅ **Статус:** Полностью реализовано и протестировано  
🎯 **Применение:** Архитектура с разделением storage и compute, используя S3BackedMergeTree для масштабируемого хранения данных  
📚 **Документация:** 
- [ClickHouse: Separation of Storage and Compute](https://clickhouse.com/docs/guides/separation-storage-compute)
- [ClickHouse: Configuring External Storage](https://clickhouse.com/docs/operations/storing-data#configuring-external-storage)

**Технические особенности:**
- ✅ S3 диски (`s3_disk`, `s3_cache`) с локальным кэшированием
- ✅ Storage policy `s3_main` для автоматического использования S3
- ✅ Отдельный файл конфигурации `storage_config.xml` согласно best practices ClickHouse
- ✅ Условное создание ресурсов через Terraform count
- ✅ Стабильная работа без crash-петель контейнеров

## Ключевые отличия от ch_with_backup

| Аспект | ch_with_backup | ch_with_storage |
|--------|----------------|-----------------|
| Архитектура | Монолитная | Модульная |
| Remote backup | Всегда создается | Управляется переменной |
| Логика MinIO | Проблемы с условиями | Корректные `count` |
| Масштабируемость | Ограничена | Высокая |

## Структура файлов
```
ch_with_storage/
├── main.tf                    # Корневой модуль
├── variables.tf               # Переменные 
├── outputs.tf                 # Выходы
├── terraform.tfvars           # Значения переменных
├── modules/
│   └── clickhouse-cluster/
│       ├── main.tf            # Логика кластера
│       ├── variables.tf       # Интерфейс модуля
│       ├── outputs.tf         # Выходы модуля
│       └── samples/           # Template файлы
└── env/                       # Сгенерированные env файлы
```

## Зависимости

- [MinIO Client (mc)](https://min.io/docs/minio/linux/reference/minio-mc.html)
- SSH доступ к remote хосту (при `enable_remote_backup=true`)
- Docker на локальной машине и remote хосте

---

## Техническая реализация S3BackedMergeTree

### Архитектурное решение
Интеграция S3BackedMergeTree потребовала решения нескольких технических вызовов:

**1. Модульная конфигурация**
Создан отдельный файл `storage_config.xml.tpl` согласно [рекомендациям ClickHouse](https://clickhouse.com/docs/operations/storing-data#configuring-external-storage):
```xml
<clickhouse>
  <storage_configuration>
    <disks>
      <s3_disk>
        <type>s3</type>
        <endpoint>http://minio-local-storage:9000/clickhouse-storage-bucket/</endpoint>
        <access_key_id>${minio_root_user}</access_key_id>
        <secret_access_key>${minio_root_password}</secret_access_key>
        <metadata_path>/var/lib/clickhouse/disks/s3_disk/</metadata_path>
        <skip_access_check>true</skip_access_check>
      </s3_disk>
      <s3_cache>
        <type>cache</type>
        <disk>s3_disk</disk>
        <path>/var/lib/clickhouse/disks/s3_cache/</path>
        <max_size>10Gi</max_size>
      </s3_cache>
    </disks>
    <policies>
      <s3_main>
        <volumes>
          <main>
            <disk>s3_disk</disk>
          </main>
        </volumes>
      </s3_main>
    </policies>
  </storage_configuration>
</clickhouse>
```

**2. Условные ресурсы в Terraform**
Реализованы условные ресурсы для создания конфигурации только при `storage_type=s3_ssd`:
```hcl
resource "local_file" "storage_config_xml" {
  count = var.storage_type == "s3_ssd" ? length(local.clickhouse_nodes) : 0
  # ... конфигурация файла
  depends_on = [null_resource.mk_clickhouse_dirs]
}

# Условное монтирование в контейнер
dynamic "mounts" {
  for_each = var.storage_type == "s3_ssd" ? [1] : []
  content {
    target    = "/etc/clickhouse-server/config.d/storage_config.xml"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/config.d/storage_config.xml")
    type      = "bind"
    read_only = true
  }
}
```

**3. Ключевые решения**
- `skip_access_check=true` - избежание crash-петель при инициализации
- Правильные зависимости через `depends_on` и `local_file.storage_config_xml`
- Endpoint с bucket в пути согласно документации
- Локальный кэш для повышения производительности

---

## FAQ / Устранение неисправностей

### Ошибка создания MinIO bucket "426 Upgrade Required"

**Проблема:** При развертывании появляется ошибка:
```
Error running command 'mc mb --ignore-existing local_storage/clickhouse-storage-bucket': exit status 1.
Output: mc: <ERROR> Unable to make bucket `local_storage/clickhouse-storage-bucket`. 426 Upgrade Required
```

**Причина:** Порт MinIO (по умолчанию 9010) занят другим процессом.

**Диагностика:**
```bash
# Проверить, что использует порт (по умолчанию 9010)
lsof -i :9010
```

**Решение:**
1. **Временное решение:** Использовать другой порт через переменную:
   ```bash
   terraform apply -auto-approve \
     -var="storage_type=s3_ssd" \
     -var="local_minio_port=9014"
   ```

2. **Постоянное решение:** Обновить порт в `terraform.tfvars`:
   ```hcl
   local_minio_port = 9014
   ```

3. **Альтернатива:** Остановить процесс, занимающий порт (если это безопасно):
   ```bash
   # Найти PID процесса
   lsof -i :9010
   # Остановить процесс (осторожно!)
   kill <PID>
   ```

**Примечание:** Обычно порт 9010 занят Logitech G HUB (`lghub_age`). В таких случаях рекомендуется использовать другой порт, а не останавливать системные процессы.

### ClickHouse ошибки "Cannot resolve host" после смены конфигурации

**Проблема:** В логах ClickHouse появляются предупреждения о недоступности несуществующих нод.

**Причина:** В S3 bucket остались метаданные из предыдущего развертывания с другой конфигурацией кластера.

**Решение:** Полная очистка перед пересозданием:
```bash
# СНАЧАЛА очистить S3 бакеты (пока MinIO еще работает)
mc rb --force local_storage/clickhouse-storage-bucket 2>/dev/null || true
mc rb --force remote_backup/clickhouse-backup-bucket 2>/dev/null || true

# Затем остановить все ресурсы
terraform destroy -auto-approve

# Пересоздать с чистого состояния
terraform apply -auto-approve -var="storage_type=s3_ssd"
```