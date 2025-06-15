# Версия пайплайна: Metabase + Superset с раздельными пользователями/БД (2025-06)

# BI-инфраструктура с Metabase и Superset на Terraform + PostgreSQL

В этом каталоге находится Terraform-конфигурация для деплоя BI-инфраструктуры с Metabase, Superset и PostgreSQL.

## Структура проекта

```
additional/bi-infra/
├── main.tf
├── variables.tf
├── outputs.tf
├── README.md
```

## Быстрый старт

### 1. Установка переменных окружения

Перед запуском Terraform задайте **обязательные** переменные окружения или используйте файл `terraform.tfvars`.

**Обязательные переменные (должны быть заданы всегда):**

```sh
export TF_VAR_metabase_pg_password="your_metabase_pg_password"
export TF_VAR_superset_pg_password="your_superset_pg_password"
export TF_VAR_superset_secret_key="your_superset_secret_key"
export TF_VAR_superset_sa_user="your_superset_admin_name"
export TF_VAR_superset_sa_password="your_superset_admin_password"
```

**Опциональные переменные** (имеют значения по умолчанию, задавать только если нужно изменить):

```sh
export TF_VAR_metabase_pg_user="metabase"                  # имя пользователя для Metabase в PostgreSQL
export TF_VAR_metabase_pg_db="metabaseappdb"               # имя БД для Metabase
export TF_VAR_metabase_port=3000                           # порт Metabase на localhost

export TF_VAR_superset_pg_user="superset"                  # имя пользователя для Superset в PostgreSQL
export TF_VAR_superset_pg_db="superset"                    # имя БД для Superset
export TF_VAR_superset_port=8088                           # порт Superset на localhost
export TF_VAR_superset_admin_email="admin@localhost"       # e-mail администратора Superset

export TF_VAR_postgres_version="17.5"                      # версия Docker-образа PostgreSQL
export TF_VAR_metabase_version="v0.55.3"                   # версия Docker-образа Metabase
export TF_VAR_superset_version="4.1.2"                     # версия Docker-образа Superset
```

> Для Metabase и Superset используются **разные пользователи и базы данных**. Пароли и секретные ключи всегда должны задаваться вручную.

### Как сгенерировать SECRET_KEY для Superset

Для генерации секретного ключа выполните:

```sh
openssl rand -base64 48 | tr -d '\n' | pbcopy
```

> Ключ вставьте в переменную `TF_VAR_superset_secret_key`.

### Как сгенерировать SECRET_KEY для Superset
> Superset 4.x требует файл superset_config.py с секретом. Всё генерируется автоматически через Terraform и шаблон: ключ берётся из переменной `superset_secret_key`, файл подставляется в контейнер.

Для генерации секретного ключа выполните:

```sh
openssl rand -base64 48 | tr -d '\n' | pbcopy
```

> Ключ будет вставлен в переменную `TF_VAR_superset_secret_key`.

### 2. Инициализация и деплой

```sh
cd additional/bi-infra
terraform init
terraform apply -auto-approve
```

> В процессе деплоя автоматически выполняются post-init команды для Superset (`superset db upgrade`, `superset init`, `superset fab create-admin`) через ресурс `null_resource` в `main.tf`. Создание суперпользователя происходит с использованием переменных `superset_pg_user`, `superset_pg_password` и `superset_admin_email`, что обеспечивает готовность Superset к работе сразу после запуска.

### 3. Доступ к сервисам после деплоя

- **Metabase**: http://localhost:3000 (порт можно изменить через переменную `metabase_port`). При первом запуске необходимо задать пароль администратора через веб-интерфейс. Для Metabase админ создается через UI при первом входе.
- **Superset**: http://localhost:8088 (порт настраивается через переменную `superset_port`). Для входа используйте логин и пароль, указанные в переменных `superset_pg_user` и `superset_pg_password`. Для Superset админ создается автоматически через post-init скрипт.

### 4. Расширение и настройка инфраструктуры

- Для добавления новых BI/ETL сервисов используйте общий PostgreSQL контейнер как backend.
- Для каждого сервиса задавайте уникальные имена баз данных при необходимости.
- Healthcheck настроены для корректного порядка запуска контейнеров и сервисов.
- Для постоянного хранения данных PostgreSQL рекомендуется добавить Docker volume в ресурс контейнера.

---

## Устранение неполадок

- Если порт занят, измените переменные `metabase_port` или `superset_port` в `variables.tf` или через переменные окружения.
- Для сохранения данных PostgreSQL используйте Docker volume, так как по умолчанию том эфемерный.
- Проверьте корректность всех переменных перед запуском.
- Логи контейнеров можно просмотреть через `docker logs <container_id>`.
- Если Superset не стартует, убедитесь, что секретный ключ действительно уникальный и не совпадает с дефолтным (должно быть не менее 32 символов).