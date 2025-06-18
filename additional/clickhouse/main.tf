terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

provider "null" {}

resource "null_resource" "install_python3" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      for c in $(docker ps --format '{{.Names}}' | grep -E '^clickhouse-[0-9]+$'); do
        echo "Checking python3 in $c"
        if ! docker exec "$c" python3 --version >/dev/null 2>&1; then
          echo "python3 not found, installing in $c"
          docker exec -u root "$c" apk update
          docker exec -u root "$c" apk add python3
        else
          echo "python3 already installed in $c"
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Универсальный шаг копирования файлов для UDF и словарей
resource "null_resource" "copy_files" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      # Генерим user_emails.csv всегда свежий перед копированием
      python3 ${path.module}/samples/gen_user_emails_csv.py

      ENABLE_COPY_UDF="${var.enable_copy_udf}"
      ENABLE_DICTIONARIES="${var.enable_dictionaries}"

      VOLUMES_PATH="${path.module}/${var.clickhouse_volumes_path}"
      for dir in "$VOLUMES_PATH"/clickhouse-*; do
        [ -d "$dir" ] || continue
        [[ "$(basename "$dir")" == *keeper* ]] && continue

        # Копирование для UDF
        if [ "$ENABLE_COPY_UDF" = "true" ]; then
          mkdir -p "$dir/data/user_scripts"
          cp ${path.module}/${var.udf_dir}/*.py "$dir/data/user_scripts/" 2>/dev/null || true
          cp ${path.module}/samples/user_defined_functions.xml "$dir/data/user_defined/" 2>/dev/null || true
          chmod +x "$dir/data/user_scripts/"*.py 2>/dev/null || true
        fi

        # Копирование xml-конфигов словарей и связанных файлов
        if [ "$ENABLE_DICTIONARIES" = "true" ]; then
          mkdir -p "$dir/data/dictionaries"
          cp ${path.module}/samples/dictionaries/*.xml "$dir/data/dictionaries/" 2>/dev/null || true
          cp ${path.module}/samples/patch_dictionaries.py "$dir/data/dictionaries/" 2>/dev/null || true
          mkdir -p "$dir/data/user_files/dictionaries"
          cp ${path.module}/samples/user_emails.csv "$dir/data/user_files/dictionaries/" 2>/dev/null || true
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [null_resource.install_python3]
}

# Патчим config.xml для каждой ClickHouse-ноды, применяя патчи для UDF и словарей по флагам
resource "null_resource" "patch_config_xml" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      ENABLE_COPY_UDF="${var.enable_copy_udf}"
      ENABLE_DICTIONARIES="${var.enable_dictionaries}"

      VOLUMES_PATH="${path.module}/${var.clickhouse_volumes_path}"
      for dir in "$VOLUMES_PATH"/clickhouse-*; do
        [ -d "$dir" ] || continue
        [[ "$(basename "$dir")" == *keeper* ]] && continue
        config_path="$dir/etc/clickhouse-server/config.d/config.xml"
        if [ -f "$config_path" ]; then
          if [ "$ENABLE_COPY_UDF" = "true" ] && [ -f "${path.module}/samples/patch_user_defined.py" ]; then
            python3 "${path.module}/samples/patch_user_defined.py" "$config_path"
            echo "Patched user_defined config for $config_path"
          fi

          # Скрипт патчит dictionaries_config для словарей
          if [ "$ENABLE_DICTIONARIES" = "true" ] && [ -f "$dir/data/dictionaries/patch_dictionaries.py" ]; then
            python3 "$dir/data/dictionaries/patch_dictionaries.py" "$config_path"
            echo "Patched dictionaries_config for $config_path"
          fi
        else
          echo "WARN: $config_path not found, skipping"
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [null_resource.copy_files]
}