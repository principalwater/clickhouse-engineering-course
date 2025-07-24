# Домашние задания по курсу "ClickHouse для инженеров и архитекторов БД"

Этот репозиторий содержит выполненные домашние задания и проекты по курсу ["ClickHouse для инженеров и архитекторов БД"](https://otus.ru/lessons/clickhouse/) от образовательной платформы OTUS.

[//]: # (----)

## ⚙️ Автоматизация CI/CD

В репозитории настроен production-ready пайплайн CI/CD на базе Github Actions. Проверка и тестирование инфраструктурного кода (Terraform) включает автоматическую валидацию, форматирование, генерацию плана изменений и загрузку артефактов при каждом pull request в основную ветку. Все секретные переменные прокидываются через Github Actions Secrets. Также выполняется автоматический lint и форматирование всех Python-скриптов. Пайплайн масштабируем и легко расширяется под новые инфраструктурные модули и интеграции. Мерж в master (main) разрешён только при успешном прохождении всех проверок.

## 📚 О курсе

**ClickHouse для инженеров и архитекторов БД** — это профессиональный курс продолжительностью 4 месяца, который охватывает все аспекты работы с ClickHouse: от установки и настройки до решений для продакшена.

### Ключевые темы курса:
- Знакомство с ClickHouse и аналитическими движками
- Работа с ClickHouse: SQL, функции, движки, индексы
- Масштабирование и манипуляции с данными
- Управление ресурсами и оптимизация
- Популярные интеграции (Kafka, BI-инструменты, PostgreSQL)
- Проектная работа

## 📁 Структура репозитория
1) [Область применения и первое представление ClickHouse](./hw01_clickhouse-adaptation/hw01.md)
2) [Развертывание и базовая конфигурация, интерфейсы и инструменты](./hw02_clickhouse-deployment)
3) [Работа с SQL в ClickHouse](./hw03_clickhouse-sql-basics)
4) [Агрегатные функции, работа с типами данных и UDF в ClickHouse](./hw04_clickhouse-functions)
5) [Движки MergeTree Family](./hw05_mergetree-engines)
6) [Джойны и агрегации](./hw06_joins-and-aggregations)
7) [Работа со словарями и оконными функциями в ClickHouse](./hw07_dictionaries-windows)
8) [Проекции и материализованные представления](./hw08_projections-materialized-views)
9) [Репликация и фоновые процессы в ClickHouse](./hw09_replication-lab)
10) [Шардирование и распределенные запросы](./hw10_sharding-distributed-queries)
11) [Мутация данных и манипуляции с партициями](./hw11_mutations-partitions)
12) [RBAC контроль доступа, квоты и ограничения](./hw12_rbac-quotas-limits)

**Дополнительно:**
- [Инфраструктурные модули и сценарии автоматизации (Terraform, Docker, ClickHouse)](./base-infra)
- [Инфраструктура BI: Metabase, Superset, Postgres (Terraform + Docker)](./additional/bi-infra)
- [Примеры, эксперименты, вспомогательные скрипты и развёртывание ClickHouse с кастомными настройками](./additional/clickhouse)

## 🎯 Цели обучения

В результате прохождения курса приобретаются навыки:
- Разворачивания и настройки ClickHouse
- Работы с базовыми и продвинутыми возможностями
- Понимания различий между ClickHouse и другими популярными БД
- Выбора подходящей конфигурации для работы с данными

## 🔧 Технологии

- **ClickHouse** — колоночная СУБД для OLAP
- **SQL** — язык запросов
- **Docker** — контейнеризация
- **Terraform** — IaaC и автоматизация развертывания
- **PostgreSQL, MySQL** — интеграции с реляционными БД
- **Apache Kafka** — потоковая обработка данных

## 📖 Дополнительные материалы

- [Официальная документация ClickHouse](https://clickhouse.com/docs)
- [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)
- [Курс на OTUS](https://otus.ru/lessons/clickhouse/)

## 👨‍💻 Автор

[Владислав Кузьмин](https://github.com/principalwater) - Data Engineer, студент курса "ClickHouse для инженеров и архитекторов БД" | OTUS

---

# Homework Assignments for "ClickHouse for DB Engineers and Architects" Course

This repository contains completed homework assignments and projects for the ["ClickHouse for DB Engineers and Architects"](https://otus.ru/lessons/clickhouse/) course from OTUS educational platform.

[//]: # (----)

## ⚙️ CI/CD Automation

This repository is equipped with a production-ready CI/CD pipeline powered by GitHub Actions. Infrastructure code (Terraform) is automatically validated, formatted, and planned with artifacts generated and uploaded on every pull request to the main branch. All sensitive variables are managed securely using GitHub Actions Secrets. All Python scripts are automatically linted and formatted as part of the pipeline. The workflow is scalable and can be easily extended for new infrastructure modules and integrations. Merging to master (main) is allowed only after all checks have passed successfully.

## 📚 About the Course

**ClickHouse for DB Engineers and Architects** is a professional 4-month course that covers all aspects of working with ClickHouse: from installation and configuration to production-ready solutions.

### Key Course Topics:
- Introduction to ClickHouse and analytical engines
- Working with ClickHouse: SQL, functions, engines, indexes
- Scaling and data manipulation
- Resource management and optimization
- Popular integrations (Kafka, BI tools, PostgreSQL)
- Project work

## 📁 Repository Structure
1) [Scope of application and initial overview of ClickHouse](./hw01_clickhouse-adaptation/hw01.md)
2) [Deployment and Basic Configuration, Interfaces and Tools](./hw02_clickhouse-deployment)
3) [Working with SQL in ClickHouse](./hw03_clickhouse-sql-basics)
4) [Aggregate Functions, Working with Data Types, and UDF in ClickHouse](./hw04_clickhouse-functions)
5) [MergeTree Engines Family](./hw05_mergetree-engines)
6) [Joins and Aggregations](./hw06_joins-and-aggregations)
7) [Dictionaries and Window Functions in ClickHouse](./hw07_dictionaries-windows)
8) [Projections and Materialized Views](./hw08_projections-materialized-views)
9) [Replication and Background Processes in ClickHouse](./hw09_replication-lab)
10) [Sharding and Distributed Queries](./hw10_sharding-distributed-queries)
11) [Data Mutation and Partition Manipulation](./hw11_mutations-partitions)
12) [RBAC Access Control, Quotas and Limits](./hw12_rbac-quotas-limits)

**Additionally:**
- [Infrastructure modules and automation scripts (Terraform, Docker, ClickHouse)](./base-infra)
- [BI Infrastructure: Metabase, Superset, Postgres (Terraform + Docker)](./additional/bi-infra)
- [Examples, experiments, helper scripts, and advanced ClickHouse deployments](./additional/clickhouse)

## 🎯 Learning Objectives

Upon completion of the course, students acquire skills in:
- Deploying and configuring ClickHouse
- Working with basic and advanced features
- Understanding differences between ClickHouse and other popular databases
- Choosing appropriate configurations for data work

## 🔧 Technologies

- **ClickHouse** — columnar DBMS for OLAP
- **SQL** — query language
- **Docker** — containerization
- **Terraform** — IaaC and deployment automatization
- **PostgreSQL, MySQL** — relational database integrations
- **Apache Kafka** — stream processing

## 📖 Additional Resources

- [Official ClickHouse Documentation](https://clickhouse.com/docs)
- [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)
- [Course on OTUS](https://otus.ru/lessons/clickhouse/)

## 👨‍💻 Author

[Vladislav Kuzmin](https://github.com/principalwater) - Data Engineer, student of "ClickHouse for DB Engineers and Architects" course | OTUS
