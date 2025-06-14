# Metabase + PostgreSQL Terraform инфраструктура
В указанном каталоге расположен Terraform-пайплайн для деплоймента дополнительных инструментов.

## Структура
```
additional/metabase-infra/
├── main.tf
├── variables.tf
├── outputs.tf
├── README.md
```
## Быстрый старт

### 1. Установите переменные окружения

```sh
export TF_VAR_pg_password="your_strong_password"
# (опционально) export TF_VAR_pg_user, TF_VAR_pg_db, TF_VAR_metabase_version, TF_VAR_postgres_version
```

### 2. Инициализация и деплой
```sh
cd additional/metabase-infra
terraform init
terraform apply -auto-approve
```

### 3. Откройте Metabase
После завершения terraform apply, Metabase будет доступен по адресу:
`http://localhost:3000`

> (При первом входе потребуется задать пароль администратора/настройку.)

### 4. Расширение новыми BI/ETL сервисами
- Добавьте новые ресурсы в main.tf, используя общий контейнер postgres как backend.
- Изменяйте только имя БД/пользователя, если нужно для других инструментов.

Примечания
- Все версии контейнеров зафиксированы и могут быть настроены через variables.tf.
- Для секретов предпочтительно использовать переменные окружения (export TF_VAR_pg_password=...) или terraform.tfvars.
- Healthcheck’и обеспечивают запуск сервисов до запуска зависимых контейнеров.
- Теперь вы можете использовать Metabase SQL Lab для интерактивной аналитики и дашбордов.

Устранение неполадок
- Если порт занят, измените metabase_port в variables.tf или через переменную окружения.
- Том Postgres является эфемерным — для постоянного хранения добавьте Docker volume в ресурс контейнера.