# Custom ClickHouse Patch & UDF Pipeline

## Назначение

Этот каталог предназначен для кастомизации уже запущенного кластера ClickHouse (развёрнутого через [base-infra/clickhouse](../../base-infra/)), без потери или изменения существующих данных, users и volumes.

**Возможности:**
- Массовое добавление или обновление UDF (Python-функций) для всех контейнеров
- Патчинг XML-конфигов контейнеров (например, секции `<user_defined>`)
- Доустановка нужных утилит внутрь контейнеров (например, python3)
- Лёгкие post-deploy правки без пересоздания кластеров или потери данных

## Управление этапами пайплайна

C помощью переменных (`enable_copy_udf`, `enable_copy_dictionaries`) можно независимо включать/отключать этапы:
- копирование UDF-файлов (Python-скриптов и xml-файла определений)
- копирование файлов словарей (csv/xml, например для dictionary engine)
Это позволяет быстро запускать только нужные этапы при тестировании или развертывании.

---

## Быстрый старт

### 1. Подготовьте окружение

Перейдите в каталог [additional/clickhouse](.) и создайте виртуальное окружение для Python:

```bash
python3 -m venv venv
source venv/bin/activate
pip install lxml
```
*(lxml требуется для корректной работы патчера XML-конфигов)*

---

### 2. Проверьте структуру

- Все .py-функции для UDF должны лежать в [`user_scripts/`](./user_scripts)
- Файл с определениями UDF — [`samples/user_defined_functions.xml`](./samples/user_defined_functions.xml)
- Патчер для config.xml — [`samples/patch_user_defined.py`](./samples/patch_user_defined.py)

---

### 3. Настройте конфигурацию

При необходимости скорректируйте файлы:
- [`main.tf`](./main.tf) — все шаги автоматизации через Terraform.
- [`variables.tf`](./variables.tf) — корректные пути к volume кластера ClickHouse (по умолчанию — `../../base-infra/clickhouse/volumes`).

---

### 4. Настройка переменных

Для управления этапами пайплайна используйте переменные `enable_copy_udf` и `enable_copy_dictionaries`. Их можно задать в файле `terraform.tfvars` или через переменные окружения. Пример для `terraform.tfvars`:

```hcl
enable_copy_udf = true
enable_copy_dictionaries = false
```

Альтернативно, можно передать значения переменных напрямую при запуске terraform:

```bash
terraform apply -auto-approve -var="enable_copy_udf=true" -var="enable_copy_dictionaries=false"
```

Это позволит включать или отключать копирование UDF и файлов словарей независимо друг от друга.

---

### 5. Примените изменения

```bash
terraform init
terraform apply -auto-approve
```

---

### 6. Копирование файлов словарей

Файлы словарей (csv, xml и другие), используемые в dictionary engine ClickHouse, теперь можно копировать опционально в volume всех ClickHouse-нод. Это удобно для обновления или добавления новых словарей без пересоздания кластеров. Для этого включите флаг `enable_copy_dictionaries`. Если он выключен, файлы словарей не копируются.

---

### (Optional) 7. Перезапустите контейнеры ClickHouse

```bash
docker restart $(docker ps --format '{{.Names}}' | grep '^clickhouse-' | grep -v keeper)
```

Это может потребоваться для применения новых UDF и конфигов без пересоздания кластера, но фактически новые функции должны быть сразу доступны и без перезагрузки.

---

**Что делает автоматизация:**
- Копирует UDF-файлы и XML-файл с описанием функций во все ClickHouse-ноды (кроме keeper)
- Устанавливает python3 в контейнеры (через apk)
- Патчит конфиг-файл `config.xml` каждой ноды для активации пользовательских функций
- Устанавливает права на исполнение для всех Python-скриптов

---

## Проверка UDF-функций на синтетических данных

Протестировать UDF можно прямо в ClickHouse, не используя реальные таблицы. Примеры:

### Пример: total_cost (2 аргумента)

```sql
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

### Пример: classify_transaction (4 аргумента)

```sql
SELECT
    price,
    quantity,
    product_id,
    user_id,
    classify_transaction(price, quantity, product_id, user_id) AS transaction_type
FROM
(
    -- large_purchase
    SELECT 1500 as price, 2 as quantity, 501 as product_id, 110 as user_id UNION ALL
    -- rare_product
    SELECT 100, 1, 521, 200 UNION ALL
    -- regular
    SELECT 20, 1, 503, 130 UNION ALL
    -- frequent_buyer
    SELECT 10, 1, 502, 119
)
ORDER BY price DESC;
```

### Пример: detect_fraud (3 аргумента)

```sql
SELECT
    price,
    product_id,
    transaction_date,
    detect_fraud(price, product_id, transaction_date) AS fraud_flag
FROM
(
    SELECT 2200 as price, 600 as product_id, '2024-06-16' as transaction_date UNION ALL
    SELECT 500, 591, '2024-06-17' UNION ALL
    SELECT 5000, 599, '2024-06-16'
);
```

### Пример: test_function_python (1 аргумент)

```sql
SELECT
    number AS value,
    test_function_python(number) AS output
FROM numbers(5);
```

---

## FAQ

- **Удалятся ли данные?**  
  Нет, все действия происходят только в live-контейнерах. Данные и users не затрагиваются.

- **Как добавить новые пакеты внутрь всех контейнеров?**  
  Используйте паттерн из ресурса `install_python3` в [`main.tf`](./main.tf) — меняйте apk add на нужный пакет.

- **Как добавить новый UDF?**  
  - Добавьте Python-файл в [`user_scripts/`](./user_scripts)
  - Пропишите функцию в [`samples/user_defined_functions.xml`](./samples/user_defined_functions.xml)
  - Запустите `terraform apply`

- **Как откатить изменения?**  
  Просто перезапустите terraform apply из [base-infra/clickhouse](../../base-infra/clickhouse) — он пересоберёт оригинальные конфиги без патчей.

- **Где брать шаблоны конфигов?**  
  В каталоге [`base-infra/clickhouse/samples`](../../base-infra/clickhouse/samples).

- **Как включить/отключить отдельные этапы пайплайна?**  
  Используйте переменные `enable_copy_udf` и `enable_copy_dictionaries` в `terraform.tfvars` или через переменные окружения. Например:

  ```hcl
  enable_copy_udf = true
  enable_copy_dictionaries = false
  ```

---

## Примечания и узкие места

- Если добавляете патчер или дополнительный скрипт — не забывайте обновлять права на выполнение (`chmod +x ...`).
- Проверяйте, что на всех нодах установлен python3 (Terraform сам его поставит, если вы не убирали install_python3).
- Любые проблемы с XML — сначала проверьте, что патчер запускается в активированном venv и lxml установлен.
- Раздельное управление этапами пайплайна (UDF/словари) позволяет гибко тестировать отдельные сценарии, не перепровиженивая всё.

---

**Каталог предназначен для безопасных post-deploy изменений — не требует пересоздания кластера!**

---

Если нужна индивидуальная логика под новые UDF или хотите добавить дополнительную автоматизацию — расширяйте [`main.tf`](./main.tf) по аналогии с текущими ресурсами.