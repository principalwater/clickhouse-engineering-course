# Расширяемый пайплайн кастомизации ClickHouse (UDF, словари и патчи)

## Назначение

Этот каталог предназначен для  пост-кастомизации уже запущенного кластера ClickHouse, который был развернут через базовый пайплайн из каталога [`base-infra/clickhouse`](../../base-infra/clickhouse). Основная задача — добавить или обновить пользовательские функции (UDF), патчи конфигурации и дополнительные файлы (например, словари) без потери данных, пользователей и без пересоздания кластера.

Данный пайплайн позволяет:

- Массово копировать Python-скрипты с UDF во все ноды ClickHouse (кроме keeper)
- Обновлять XML-файл с описанием пользовательских функций (`user_defined_functions.xml`)
- Патчить конфигурационные файлы `config.xml` для активации UDF
- Копировать дополнительные файлы словарей (csv, xml) в volume кластера
- Устанавливать необходимые утилиты (например, python3) внутри контейнеров
- Управлять этапами пайплайна через переменные, включая опциональное копирование UDF и словарей

Все изменения применяются к уже запущенному кластеру без его пересоздания и не затрагивают данные или пользователей.

---

## Структура каталога

- `.terraform/`                  — служебные файлы и плагины Terraform (создаётся автоматически)
- `.terraform.lock.hcl`.         — lock-файл зависимостей Terraform
- `main.tf`                      — основной Terraform-манифест (логика копирования файлов, патчинга конфигов и установки пакетов внутри контейнеров ClickHouse)
- `variables.tf`.                — описание переменных Terraform, включая пути к volume кластера, флаги включения этапов (UDF, словари) и другие параметры
- `outputs.tf`                   — выводы Terraform для мониторинга и интеграции
- `samples/`                     — вспомогательные файлы и скрипты:
    - gen_user_emails_csv.py     — генерация тестового .csv для словаря email
    - patch_dictionaries.py      — скрипт патчинга config.xml для подключения словарей
    - patch_user_defined.py      — скрипт патчинга config.xml для UDF
    - user_defined_functions.xml — XML с описанием UDF для ClickHouse
    - user_emails.csv            — автогенерируемый .csv для примера словаря
    - `dictionaries/`            — каталог с xml-конфигами словарей (например, user_email_dict.xml)
- `user_scripts/`                — директория с Python-скриптами, реализующими UDF (копируются на все ClickHouse-ноды)
    - classify_transaction.py, detect_fraud.py, test_function.py, total_cost.py (и др.)
- `terraform.tfstate`            — состояние Terraform (создаётся автоматически)
- `terraform.tfstate.backup`     — бэкап состояния Terraform (создаётся автоматически)
- `venv/`                        — виртуальное окружение Python (создаётся вручную для запуска скриптов патчинга XML)
- `README.md`                    — данный файл с документацией по работе каталога

---

## Инструкция по развертыванию и использованию

### 1. Предварительное условие: базовый кластер

Перед использованием данного пайплайна необходимо развернуть базовый кластер ClickHouse с помощью пайплайна из каталога [`base-infra/clickhouse`](../../base-infra/clickhouse). Этот базовый пайплайн создаёт все контейнеры, тома и базовые конфигурации.

---

### 2. Настройка Python окружения

Для корректной работы патчера XML-конфигов требуется Python с установленным пакетом `lxml`.

```bash
cd additional/clickhouse
python3 -m venv venv
source venv/bin/activate
pip install lxml
```

---

### 3. Настройка переменных Terraform

Для управления этапами пайплайна и путями к volume кластера используйте файл `terraform.tfvars` или задавайте переменные через командную строку.

Пример `terraform.tfvars`:

```hcl
enable_eudf = true
enable_dictionaries = false
clickhouse_volumes_path = "../../base-infra/clickhouse/volumes"
udf_dir = "user_scripts"
dict_samples_dir = "samples"
```

- `enable_eudf` — Флаг для включения/отключения шага с копированием executable UDF конфигов и самих функций.
- `enable_dictionaries` — Флаг для включения/отключения шага с копированием XML-конфигов словарей и их данных.
- `enable_copy_additional_configs` — включает копирование дополнительных конфигов и патчей.
- `clickhouse_volumes_path` — Путь к volume с данными и конфигами кластера.
- `udf_dir` — Каталог с Python-скриптами UDF.
- `dict_samples_dir` — Каталог с примерами файлов словарей.

> **Примечание:** Если вызвать `terraform apply -auto-approve` без явного задания переменных (в `terraform.tfvars` или через CLI), будут выполнены только шаги по патчингу UDF (копирование UDF-скриптов и патч `config.xml`). Этапы, связанные со словарями, не затрагиваются.

---

### 4. Применение пайплайна

Запустите Terraform:

```bash
terraform init
terraform apply -auto-approve
```

Пайплайн выполнит следующие действия:

- Копирует Python-скрипты из `user_scripts/` и `user_defined_functions.xml` из `samples/` во все ClickHouse-ноды (кроме keeper) при включённом `enable_eudf`.
- Копирует файлы словарей из соответствующих директорий в volume при включённом `enable_dictionaries`.
- Патчит `config.xml` каждой ноды с помощью скрипта `patch_user_defined.py` для активации пользовательских функций.
- Устанавливает python3 и другие утилиты внутри контейнеров (через apk).
- Устанавливает права на исполнение для всех Python-скриптов.

---

### 5. Проверка успешного применения

- Проверьте логи Terraform на предмет ошибок.
- Рестарт контейнеров для применения изменений делать не нужно — все изменения применяются "на лету".

Если потребуется принудительный рестарт, можно использовать команду:

```bash
docker restart $(docker ps --format '{{.Names}}' | grep '^clickhouse-' | grep -v keeper)
```

- Выполните тестовые запросы к UDF и словарям в ClickHouse (см. примеры ниже).

---

## Работа с UDF и словарями

- Чтобы активировать пользовательские функции через executable UDF, включите `enable_eudf = true`.
  - Python-файлы из `user_scripts/` копируются в контейнеры.
  - Файл `samples/user_defined_functions.xml` копируется и используется для регистрации функций.
  - Конфигурация `config.xml` каждой ноды патчится для активации UDF.
- Чтобы активировать копирование словарей, включите `enable_dictionaries = true`.
  - Файлы словарей (csv, xml и др.) копируются в соответствующие тома кластера.
- Все операции безопасны и не требуют пересоздания кластера или потери данных.

---

## Восстановление исходного состояния

Для отката кастомизации просто выполните повторный запуск базового пайплайна из [`base-infra/clickhouse`](../../base-infra/clickhouse). Он восстановит оригинальные конфигурации без патчей и пользовательских функций.

---

## Примеры переменных для Terraform

```hcl
enable_eudf = true
enable_dictionaries = false
clickhouse_volumes_path = "../../base-infra/clickhouse/volumes"
udf_dir = "user_scripts"
dict_samples_dir = "samples"
```

---

## Важные ссылки

- [Базовый пайплайн ClickHouse](../../base-infra/clickhouse)
- [Документация Terraform](https://www.terraform.io/)
- [lxml для Python](https://lxml.de/)

---

## Примеры тестов в ClickHouse

```sql
SELECT test_function_python(1);

SELECT
    price,
    quantity,
    total_cost(price, quantity) AS total
FROM
(
    SELECT
        number + 1 AS price,
        number * 2 AS quantity
    FROM numbers(5)
);
```

```sql
SELECT dictGet('user_email_dict', 'email', toUInt64(1002)) AS email;

SELECT *
FROM dictionary('user_email_dict')
LIMIT 10;
```

---

## Примечания

- Все операции выполняются на запущенных контейнерах, данные и пользователи не затрагиваются.
- Для корректной работы патчинга XML обязательно активируйте Python virtualenv с установленным `lxml`.
- Управление этапами пайплайна через переменные позволяет гибко тестировать и разворачивать изменения без полного пересоздания кластера.
- При добавлении новых UDF добавляйте Python-скрипты в `user_scripts/` и обновляйте `samples/user_defined_functions.xml`.

---

**Каталог предназначен для безопасных post-deploy изменений без пересоздания кластера!**

---

## FAQ. Типовые проблемы и их решение

- **Ошибка FILE_DOESNT_EXIST**: Проверьте, что .csv-файл словаря действительно находится в нужном каталоге (обычно `/var/lib/clickhouse/user_files/` или `/var/lib/clickhouse/user_files/dictionaries/` внутри volume).
- **Ошибка PATH_ACCESS_DENIED**: Проверьте, что путь к .csv-файлу находится строго внутри `/var/lib/clickhouse/user_files/` (или вложенной папки) — ClickHouse не разрешает читать словари из других путей.
- **dictGet возвращает NULL или ошибку**: Убедитесь, что словарь корректно создан, файл .csv существует на всех нодах и права на чтение установлены.
- **Изменения не применяются**: Проверьте логи Terraform, убедитесь, что команда патчинга `config.xml` и копирования файлов прошла успешно; при необходимости пересоздайте volume или повторите копирование.