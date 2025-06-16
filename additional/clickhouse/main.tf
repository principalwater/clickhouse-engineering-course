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
        echo "Installing python3 in $c"
        docker exec -u root "$c" apk update
        docker exec -u root "$c" apk add python3
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 1. Копируем UDF-файлы и XML-файл в volume каждой ClickHouse-ноды
resource "null_resource" "copy_udf_files" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      VOLUMES_PATH="${path.module}/${var.clickhouse_volumes_path}"
      for dir in "$VOLUMES_PATH"/clickhouse-*; do
        [ -d "$dir" ] || continue
        [[ "$(basename "$dir")" == *keeper* ]] && continue
        mkdir -p "$dir/data/user_scripts"
        mkdir -p "$dir/data/user_defined"
        cp ${path.module}/${var.udf_dir}/*.py "$dir/data/user_scripts/"
        cp ${path.module}/samples/user_defined_functions.xml "$dir/data/user_defined/"
        chmod +x "$dir/data/user_scripts/"*.py
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [null_resource.install_python3]
}

# 2. Патчим config.xml для каждой ClickHouse-ноды
resource "null_resource" "patch_config_xml" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOT
      VOLUMES_PATH="${path.module}/${var.clickhouse_volumes_path}"
      for dir in "$VOLUMES_PATH"/clickhouse-*; do
        [ -d "$dir" ] || continue
        [[ "$(basename "$dir")" == *keeper* ]] && continue
        config_path="$dir/etc/clickhouse-server/config.d/config.xml"
        if [ -f "$config_path" ]; then
          python3 "${path.module}/samples/patch_user_defined.py" "$config_path"
          echo "Patched $config_path"
        else
          echo "WARN: $config_path not found, skipping"
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [null_resource.copy_udf_files]
}