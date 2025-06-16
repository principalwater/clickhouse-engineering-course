# Homework #4: Агрегатные функции, работа с типами данных и UDF в ClickHouse

## Общее описание задания

_Примечание: Все SELECT-запросы (не DDL) выполнялись из интерфейса Metabase, развернутого через Terraform-пайплайн из каталога `../additional/bi-infra`. Metabase подключён к кластеру ClickHouse (`dwh_test`) по протоколу HTTP (порт 8123) через ClickHouse Keeper. Такой подход позволяет выполнять запросы из удобного UI, оперативно видеть результаты и получать скриншоты непосредственно из интерфейса бизнес-аналитики._

Цель: Научиться работать с агрегатными функциями, типами данных и пользовательскими функциями (UDF) в ClickHouse.

Задачи:
- Создать базу данных и таблицу для хранения транзакций.
- Заполнить таблицу тестовыми данными с заданным распределением.
- Выполнить запросы с использованием агрегатных функций для анализа данных.
- Применить функции для работы с типами данных.
- Создать и использовать пользовательские функции (UDF) на примере Python.

Критерии оценки:
- Корректность и полнота выполнения всех пунктов задания.
- Использование всех требуемых SQL-конструкций и функций.
- Наличие скриншотов с результатами выполнения запросов.
- Правильное создание и применение UDF.

---

## Предварительная подготовка

### Создание базы данных `otus_default`

_SQL:_  
```sql
CREATE DATABASE IF NOT EXISTS otus_default ON CLUSTER dwh_test;
```

_Комментарий:_ Создание базы данных с использованием кластера `dwh_test`.  

### Создание таблицы `transactions`

_SQL:_  
```sql
CREATE TABLE otus_default.transactions
ON CLUSTER dwh_test
(
    transaction_id   UInt32,
    user_id          UInt32,
    product_id       UInt32,
    quantity         UInt8,
    price            Float32,
    transaction_date Date
)
ENGINE = MergeTree()
ORDER BY (transaction_id);
```

_Комментарий:_ Создание таблицы с необходимой структурой и типами данных на кластере `dwh_test`.  

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/00_1_create_transactions_table.png" alt="Создание БД и таблицы transactions" width="600"/>

---

### Заполнение таблицы тестовыми данными

### Для теста в задании испольузуется вставка 5 миллионов строк с распределением по user_id, product_id, quantity, price и дате

_SQL:_  
```sql
INSERT INTO otus_default.transactions
SELECT
    number + 1 AS transaction_id,
    -- С вероятностью 70% user_id от 101 до 120, с 30% — от 121 до 200
    if(rand() % 10 < 7, 101 + intDiv(rand(), 100000000) % 20, 121 + intDiv(rand(), 100000000) % 80) AS user_id,
    -- Чаще встречаются популярные продукты: с вероятностью 60% product_id от 501 до 510, иначе от 511 до 600
    if(rand() % 10 < 6, 501 + intDiv(rand(), 1000000) % 10, 511 + intDiv(rand(), 1000000) % 90) AS product_id,
    -- quantity: 70% — 1–2, 20% — 3–5, 10% — 6–10
    multiIf(rand() % 10 < 7, 1 + rand() % 2, rand() % 10 < 9, 3 + rand() % 3, 6 + rand() % 5) AS quantity,
    -- price: популярные товары дешевле, остальные дороже, немного шума
    if(product_id <= 510, 5 + rand() % 1000 / 100, 20 + rand() % 4000 / 100) + (rand() % 1000) / 10000.0 AS price,
    -- Даты транзакций распределены по июню 2024 г.
    toDate('2024-06-01') + intDiv(number, 166666) % 30 AS transaction_date
FROM numbers(5000000);
```

_Комментарий:_ Заполнение таблицы с распределением значений и смещением для имитации реальных данных.  

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/00_2_insert_data.png" alt="Вставка тестовых данных" width="600"/>

---

## 1. Агрегатные функции

_SQL:_  
```sql
SELECT 
    sum(price * quantity) AS total_revenue,
    avg(price * quantity) AS avg_revenue_per_transaction,
    sum(quantity) AS total_quantity_sold,
    count(DISTINCT user_id) AS unique_buyers
FROM otus_default.transactions;
```

_Комментарий:_  
- Общий доход рассчитывается как сумма произведений цены и количества по всем транзакциям.  
- Средний доход с одной сделки — среднее значение произведения цены и количества.  
- Общее количество проданной продукции — сумма всех quantity по транзакциям.  
- Количество уникальных пользователей определяется подсчётом уникальных user_id.  

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/01_total_revenue.png" alt="Общий доход от всех операций" width="800"/>

---

## 2. Функции для работы с типами данных

_SQL:_
```sql
SELECT
  transaction_id,
  toString(transaction_date) AS transaction_date_str,
  substring(transaction_date_str, 1, 4) AS year_substring,
  substring(transaction_date_str, 6, 2) AS month_substring,
  splitByChar('-', transaction_date_str)[1] AS year_by_split,
  splitByChar('-', transaction_date_str)[2] AS month_by_split,
  toYear(transaction_date) AS year_func,
  toMonth(transaction_date) AS month_func,
  price,
  round(price) AS rounded_price,
  toString(transaction_id) AS transaction_id_str
FROM otus_default.transactions
LIMIT 5;
```

_Комментарий:_
- Преобразование даты в строку (YYYY-MM-DD) и дальнейшее извлечение года/месяца из этой строки.
- Год и месяц транзакции определяются несколькими способами:
    - **Извлечение подстрок:** `substring(transaction_date_str, 1, 4)` — год, `substring(transaction_date_str, 6, 2)` — месяц;
    - **Разделение строки по символу '-':** `splitByChar('-', transaction_date_str)[1]` — год, `[2]` — месяц;
    - **Встроенные функции ClickHouse:** `toYear(transaction_date)`, `toMonth(transaction_date)`.
- Округление цены и преобразование transaction_id в строку.
- Все операции демонстрируются в одном запросе для наглядности.

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/02_all_datatype_functions.png" alt="Функции для работы с типами данных" width="800"/>

---

## 3. User-Defined Functions (UDFs)

Пользовательские функции на Python (UDF) автоматически размещаются и регистрируются в кластере ClickHouse с помощью отдельного Terraform-пайплайна в каталоге [`../additional/clickhouse/`](../additional/clickhouse/).

**Архитектура и структура:**
- Все исходные Python-функции (UDF) помещаются в `../additional/clickhouse/clickhouse-udf/`.
    - Пример: `total_cost.py`, `classify_transaction.py`
- Примеры и шаблоны для расширения пайплайна — в `../additional/clickhouse/samples/`
- Основной terraform-файл пайплайна: [`main.tf`](../additional/clickhouse/main.tf)

**Описание важнейших параметров пайплайна:**
- Автоматически копирует все Python-файлы UDF из каталога `clickhouse-udf/` во все контейнеры clickhouse-server кластера.
- Автоматически патчит файл `config.xml` на каждом сервере ClickHouse для регистрации новых функций.
- Позволяет гибко расширять каталог UDF: любые новые функции просто добавляются в каталог и автоматически подключаются при следующем запуске пайплайна.
- Для применения изменений поддерживается динамический reload конфигурации clickhouse-server (или перезапуск контейнера, если требуется).

**ВАЖНО:**  
Данный пайплайн НЕ разворачивает сам кластер ClickHouse — он применяется только на уже развернутый и функционирующий кластер, например, после запуска пайплайна из [`../hw02_clickhouse-deployment/Terraform/main.tf`](../hw02_clickhouse-deployment/Terraform/main.tf).

Подробная инструкция и код пайплайна доступны по ссылке:  
[`../additional/clickhouse/main.tf`](../additional/clickhouse/main.tf)

### 3.1. Создайте простую UDF для расчета общей стоимости транзакции.

_Файл total_cost.py (Terraform копирует в /var/lib/clickhouse/user_defined/total_cost.py):_

```python
def total_cost(price, quantity):
    return price * quantity
```
> Функция принимает цену и количество, возвращая общую стоимость транзакции.

_Комментарий:_ Файл размещается автоматически через Terraform, ручных действий не требуется.

---

### 3.2. Используйте созданную UDF для расчета общей цены для каждой транзакции.

_SQL:_  
```sql
SELECT
  transaction_id,
  price,
  quantity,
  total_cost(price, quantity) AS total_transaction_cost
FROM otus_default.transactions
LIMIT 5;
```

_Комментарий:_ Вызов пользовательской функции total_cost для вычисления общей стоимости каждой транзакции.

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/06_2_total_cost_udf.png" alt="Расчет общей стоимости транзакции с помощью UDF" width="600"/>

### 3.3. Создайте UDF для классификации транзакций на «высокоценные» и «малоценные» на основе порогового значения (например, 100).

_Пример Python UDF (transaction_classification.py):_

```python
def classify_transaction(total_cost):
    if total_cost >= 100:
        return 'high_value'
    else:
        return 'low_value'
```
> _Файл classify_transaction.py (Terraform копирует в /var/lib/clickhouse/user_defined/classify_transaction.py):_

_Комментарий:_ Функция классифицирует транзакции по стоимости.

---

### 3.4. Примените UDF для категоризации каждой транзакции.

_SQL:_  
```sql
SELECT
  transaction_id,
  total_cost(price, quantity) AS total_transaction_cost,
  classify_transaction(total_cost(price, quantity)) AS transaction_category
FROM otus_default.transactions
LIMIT 5;
```

_Комментарий:_  
UDF для расчёта стоимости и классификации транзакций уже зарегистрированы через пайплайн, их вызов доступен без дополнительных манипуляций.

_Скриншот:_  
<img src="../screenshots/hw04_clickhouse-functions/06_4_transaction_classification_udf.png" alt="Категоризация транзакций с помощью UDF" width="600"/>

---

---

## Итоги

- Все пункты задания по варианту 1 выполнены на примере тестовых транзакций, с применением всех требуемых SQL-конструкций и функций.  
- Для проверки выполнения задания приложены SQL-запросы и скриншоты работы в кластере ClickHouse.