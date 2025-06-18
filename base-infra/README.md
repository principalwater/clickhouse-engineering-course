# Общие сведения и платформы

> **ВНИМАНИЕ:** Все инструкции, скрипты и примеры приведены преимущественно для macOS (основная среда разработки автора — Macbook Air/Mac Studio). Для Linux и Windows приведены отдельные команды, но если возникают отличия, в первую очередь проверяйте их для macOS.

---

# Клонирование репозитория и установка Docker

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/yourname/clickhouse-engineering-course.git
   cd clickhouse-engineering-course
   ```
2. Установите Docker:
   - **macOS:** Скачайте и установите [Docker Desktop для Mac](https://www.docker.com/products/docker-desktop/)
   - **Linux:** Следуйте [официальной инструкции](https://docs.docker.com/engine/install/)
   - **Windows:** Скачайте и установите [Docker Desktop для Windows](https://www.docker.com/products/docker-desktop/)

> Для macOS альтернативно (и первостепенно) рекомендуется установить Docker через Homebrew:
> ```bash
> brew install --cask docker
> ```

---

# ClickHouse Cluster Base Infrastructure

## Установка Terraform

> **Прежде чем использовать Terraform, убедитесь, что он установлен:**

- **macOS:**  
  ```bash
  brew install terraform
  ```
- **Linux:**  
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform
  ```
- **Windows:**  
  1. Скачайте архив с [официального сайта](https://www.terraform.io/downloads.html)
  2. Распакуйте `terraform.exe` в каталог, указанный в `PATH`

---

## Назначение и структура каталога

Данный каталог содержит основную инфраструктуру для развертывания кластера ClickHouse с использованием Terraform и Docker, с полной поддержкой сохранения данных, независимой настройки и возможности доработки кластера через дополнительные модули.

### Основная структура

```
clickhouse-engineering-course/
├── base-infra/
│   ├── clickhouse/         # Основной кластер ClickHouse: инфраструктура, конфиги, volumes
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── samples/        # Шаблоны конфигов ClickHouse
│   │   │   ├── config.xml.tpl
│   │   │   ├── keeper_config.xml.tpl
│   │   │   ├── users.xml.tpl
│   │   ├── volumes/        # Хранение всех данных, логов, конфигов кластера
│   │   │   ├── clickhouse-01/
│   │   │   ├── clickhouse-02/
│   │   │   ├── ...
│   ├── env/                # Сюда генерируется .env с секретами ClickHouse
│   │   └── clickhouse.env
├── additional/
│   ├── clickhouse/         # Скрипты доработки, пайплайны UDF, доустановка пакетов
│   ├── bi-infra/           # Интеграция с BI/аналитическими системами, драйверы и т.д.
```

- Все данные и состояние кластера ClickHouse хранятся в `volumes/`, смонтированных как bind mount в контейнеры — это гарантирует их сохранность при обновлении или пересоздании инфраструктуры.
- Основной контроль и запуск кластера ведётся из каталога `base-infra/clickhouse`.
- Все дополнительные настройки и расширения кластера выполняются из `additional/clickhouse` или других модулей в `additional/`.

---

## Важные переменные окружения

Перед запуском Terraform и sh-скриптов необходимо задать переменные для учётных данных ClickHouse:

```sh
export TF_VAR_super_user_name="<SUPERUSER_LOGIN>"
export TF_VAR_super_user_password="<SUPERUSER_PASSWORD>"
export TF_VAR_bi_user_name="<BI_USER_LOGIN>"
export TF_VAR_bi_user_password="<BI_USER_PASSWORD>"
```

> ⚠️ Без этих переменных развертывание не будет выполнено корректно.

После завершения работы обязательно очистите чувствительные переменные:

```sh
unset TF_VAR_super_user_password TF_VAR_bi_user_password
```

---

## Порядок запуска и обновления
0. Убедитесь, что вы находитесь в корне репозитория:
   ```bash
   cd clickhouse-engineering-course
   ```

1. Перейдите в каталог кластера:
   ```bash
   cd base-infra/clickhouse
   ```

2. Проверьте переменные (файл `variables.tf`). При необходимости скорректируйте параметры (имена пользователей, пути, версии, порты и др.).

3. Если требуется, перенесите актуальные директории данных/volumes в `base-infra/clickhouse/volumes` (если данные мигрировали из другого места).

4. Запустите инфраструктуру:
   ```bash
   terraform init
   terraform apply
   ```

5. Проверьте состояние контейнеров:
   ```bash
   docker ps | grep clickhouse
   ```

6. Для входа в ClickHouse используйте параметры из `.env`:
   ```bash
   docker exec -it clickhouse-01 clickhouse-client --user <user> --password <password>
   ```

---

## Расширение и поддержка

- Все кастомные доработки кластера (например, массовое добавление UDF, патчи конфигов, доустановка пакетов) рекомендуется оформлять отдельными модулями или пайплайнами в каталоге `additional/clickhouse`.
- Интеграция с BI-инструментами, настройка Metabase, Superset и других аналитических систем — в `additional/bi-infra`.
- Любые доработки не затрагивают содержимое volumes — данные всегда сохраняются.

---

## Рекомендации

- Никогда не удаляйте каталог `volumes/` без резервного копирования, если требуется сохранность данных!
- Для обновления конфигурации достаточно пересоздать только контейнеры — все данные сохранятся.
- Используйте одну точку управления для кластера — `base-infra/clickhouse`.

---

## FAQ — Часто задаваемые вопросы

### Как добавить новый UDF или обновить конфиг без потери данных?

- Используйте пайплайны из `additional/clickhouse` — они вносят изменения без удаления volumes, все данные сохраняются.

### Как изменить версию ClickHouse или параметры кластера?

- Измените переменные в `variables.tf`, затем выполните `terraform apply`. Контейнеры будут пересозданы, а данные останутся.

### Как сделать резервную копию данных?

- Просто скопируйте каталог `volumes/` целиком перед любыми обновлениями или экспериментами:
  ```bash
  cp -r volumes/ volumes_backup_$(date +%Y-%m-%d_%H-%M-%S)
  ```

### Что делать, если контейнеры ClickHouse не стартуют?

- Проверьте логи контейнеров:
  ```bash
  docker logs <container-name>
  ```
- Проверьте права на папки внутри `volumes/`.

### Как добавить новые BI-инструменты или интеграции?

- Смотрите каталоги внутри `additional/`. Обычно достаточно перейти в нужный модуль и следовать его инструкциям по запуску.

### Можно ли удалять или менять содержимое в `volumes/` вручную?

- Не рекомендуется! Все изменения производите через Terraform и подготовленные пайплайны.

---

> При возникновении вопросов по запуску или расширению инфраструктуры — используйте этот README как базовый гайд.
