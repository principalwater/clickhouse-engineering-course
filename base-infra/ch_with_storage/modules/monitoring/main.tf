###############################################################################
# ClickHouse External Monitoring Module
# Homework #14: External services only (Prometheus + Grafana + Exporter)
###############################################################################

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
  }
}

# --- Locals ---
locals {
  # Common labels for all monitoring containers
  common_labels = {
    "com.docker.compose.project" = var.project_name
    "module.name"                = "monitoring"
    "managed-by"                 = "terraform"
  }

  # Coalesce admin credentials with super_user fallback
  grafana_admin_user = coalesce(var.grafana_admin_username, var.super_user_name, "admin")
  grafana_admin_pwd  = coalesce(var.grafana_admin_password, var.super_user_password)
  grafana_admin_mail = var.grafana_admin_email
}

# --- Monitoring Network ---
resource "docker_network" "monitoring" {
  name = "${var.project_name}-monitoring-network"

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.network"
    value = "monitoring"
  }
  labels {
    label = "component.type"
    value = "network"
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }
}

# --- Docker Images ---
resource "docker_image" "prometheus" {
  name         = "prom/prometheus:latest"
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_image" "clickhouse_exporter" {
  name         = "f1yegor/clickhouse-exporter:latest"
  keep_locally = true
}

# --- Prometheus Configuration ---
resource "local_file" "prometheus_config" {
  content = templatefile("${path.module}/samples/prometheus.yml.tpl", {
    clickhouse_hosts = var.clickhouse_hosts
  })
  filename = "${path.module}/generated/prometheus.yml"

  # Create directory if it doesn't exist
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/generated"
  }
}

# --- ClickHouse Prometheus Configuration ---
resource "null_resource" "force_prometheus_config_recreation" {
  triggers = {
    always_run = timestamp()
  }
}

resource "local_file" "clickhouse_prometheus_config" {
  for_each = toset(var.clickhouse_hosts)
  content  = templatefile("${path.module}/samples/prometheus.xml.tpl", {})
  filename = "${var.clickhouse_base_path}/${split(":", each.value)[0]}/etc/clickhouse-server/config.d/prometheus.xml"

  # Force recreation on every apply to ensure template changes are applied
  lifecycle {
    replace_triggered_by = [null_resource.force_prometheus_config_recreation]
  }
}

# Cleanup old Prometheus configs on destroy
resource "null_resource" "cleanup_prometheus_config" {
  for_each = toset(var.clickhouse_hosts)

  triggers = {
    host_name = split(":", each.value)[0]
    base_path = var.clickhouse_base_path
  }

  provisioner "local-exec" {
    command = "rm -f ${self.triggers.base_path}/${self.triggers.host_name}/etc/clickhouse-server/config.d/prometheus.xml || true"
    when    = destroy
  }
}

# --- Prometheus Container ---
resource "docker_container" "prometheus" {
  name  = "prometheus-monitoring"
  image = docker_image.prometheus.name
  init  = true

  networks_advanced {
    name    = docker_network.monitoring.name
    aliases = ["prometheus"]
  }

  networks_advanced {
    name = var.clickhouse_network_name
  }

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  mounts {
    target    = "/etc/prometheus/prometheus.yml"
    source    = abspath(local_file.prometheus_config.filename)
    type      = "bind"
    read_only = true
  }

  # Additional Prometheus configuration
  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--web.console.libraries=/etc/prometheus/console_libraries",
    "--web.console.templates=/etc/prometheus/consoles",
    "--storage.tsdb.retention.time=15d",
    "--web.enable-lifecycle"
  ]

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "prometheus"
  }
  labels {
    label = "component.type"
    value = "prometheus"
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }

  depends_on = [local_file.prometheus_config]
}

# --- Grafana Container ---
resource "docker_container" "grafana" {
  name  = "grafana-monitoring"
  image = docker_image.grafana.name
  init  = true

  networks_advanced {
    name    = docker_network.monitoring.name
    aliases = ["grafana"]
  }

  ports {
    internal = 3000
    external = var.grafana_port
  }

  env = [
    "GF_SECURITY_ADMIN_USER=${local.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${local.grafana_admin_pwd}",
    "GF_SECURITY_ADMIN_EMAIL=${local.grafana_admin_mail}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_SECURITY_ALLOW_EMBEDDING=true",
    "GF_SECURITY_COOKIE_SAMESITE=none",
    "GF_INSTALL_PLUGINS=grafana-clickhouse-datasource"
  ]

  # Grafana storage
  volumes {
    volume_name    = "grafana-storage"
    container_path = "/var/lib/grafana"
  }

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "grafana"
  }
  labels {
    label = "component.type"
    value = "grafana"
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }
}

# --- ClickHouse Exporter Container ---
resource "docker_container" "clickhouse_exporter" {
  name  = "clickhouse-exporter"
  image = docker_image.clickhouse_exporter.name
  init  = true

  networks_advanced {
    name    = docker_network.monitoring.name
    aliases = ["clickhouse-exporter"]
  }

  networks_advanced {
    name = var.clickhouse_network_name
  }

  ports {
    internal = 9116
    external = var.clickhouse_exporter_port
  }

  env = [
    "CLICKHOUSE_USER=${var.clickhouse_user}",
    "CLICKHOUSE_PASSWORD=${var.clickhouse_password}",
    "CLICKHOUSE_DATABASE=default"
  ]

  # Configure exporter to use correct ClickHouse URI
  command = [
    "-scrape_uri", "${var.clickhouse_uri}",
    "-telemetry.address", ":9116"
  ]

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "com.docker.compose.service"
    value = "clickhouse-exporter"
  }
  labels {
    label = "component.type"
    value = "clickhouse-exporter"
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }
}

# --- Grafana Volume ---
resource "docker_volume" "grafana_storage" {
  name = "grafana-storage"

  labels {
    label = "com.docker.compose.project"
    value = var.project_name
  }
  labels {
    label = "component.type"
    value = "volume"
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }
}

# --- Wait for services to be ready ---
resource "null_resource" "wait_for_prometheus" {
  provisioner "local-exec" {
    command = <<EOT
      for i in {1..30}; do
        if curl -s http://localhost:${var.prometheus_port}/-/ready > /dev/null; then
          echo "Prometheus is ready!"
          break
        fi
        echo "Attempt $i/30 - Prometheus not ready yet, waiting 10 seconds..."
        sleep 10
      done
    EOT
  }

  depends_on = [docker_container.prometheus]
}

resource "null_resource" "wait_for_grafana" {
  provisioner "local-exec" {
    command = <<EOT
      for i in {1..30}; do
        if curl -s http://localhost:${var.grafana_port}/api/health > /dev/null; then
          echo "Grafana is ready!"
          break
        fi
        echo "Attempt $i/30 - Grafana not ready yet, waiting 10 seconds..."
        sleep 10
      done
    EOT
  }

  depends_on = [docker_container.grafana]
}

# --- Grafana Admin User Setup ---
resource "null_resource" "grafana_admin_setup" {
  provisioner "local-exec" {
    command     = <<EOT
set -e

GRAFANA_URL="http://localhost:${var.grafana_port}"
ADMIN_USER="${local.grafana_admin_user}"
ADMIN_PASSWORD="${local.grafana_admin_pwd}"
ADMIN_EMAIL="${local.grafana_admin_mail}"

# Wait for Grafana to become healthy
echo "Waiting for Grafana to become ready..."
for i in {1..30}; do
  if curl -sf "$GRAFANA_URL/api/health" > /dev/null; then
    echo "Grafana is healthy"
    break
  else
    echo "Waiting for Grafana to be healthy... ($i/30)"
    sleep 5
  fi
  if [ $i -eq 30 ]; then
    echo "ERROR: Grafana is not healthy after 2.5 minutes"
    exit 1
  fi
done

# Check if default admin user exists and can authenticate
echo "Checking admin user authentication..."
AUTH_CHECK=$(curl -sf -u "$ADMIN_USER:$ADMIN_PASSWORD" "$GRAFANA_URL/api/user" || echo "failed")

if [ "$AUTH_CHECK" = "failed" ]; then
  echo "WARNING: Admin user authentication failed. This might be expected on first setup."
  echo "Grafana container should have created the admin user automatically via environment variables."
else
  echo "Admin user authentication successful"
  echo "Admin user details: $AUTH_CHECK"
fi

echo "Admin user setup completed"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [null_resource.wait_for_grafana]
}

# --- Grafana Additional Users Creation ---
resource "null_resource" "grafana_create_users" {
  count = length(var.grafana_local_users) > 0 ? 1 : 0

  provisioner "local-exec" {
    command     = <<EOT
set -e

GRAFANA_URL="http://localhost:${var.grafana_port}"
ADMIN_USER="${local.grafana_admin_user}"
ADMIN_PASSWORD="${local.grafana_admin_pwd}"

echo "Creating additional Grafana users..."

# Create users from grafana_local_users variable
echo '${jsonencode(var.grafana_local_users)}' | jq -c '.[]' | while read -r user; do
  username=$(echo "$user" | jq -r '.username')
  password=$(echo "$user" | jq -r '.password')
  first_name=$(echo "$user" | jq -r '.first_name // ""')
  last_name=$(echo "$user" | jq -r '.last_name // ""')
  email=$(echo "$user" | jq -r '.email')
  role=$(echo "$user" | jq -r '.role // "Viewer"')
  
  echo "Creating Grafana user: $username with role: $role"
  
  # Check if user exists
  EXISTING=$(curl -sf -u "$ADMIN_USER:$ADMIN_PASSWORD" \
    "$GRAFANA_URL/api/users/search?query=$username" | jq -r '.users[]? | select(.login=="'"$username"'") | .id' || true)
  
  if [ -n "$EXISTING" ]; then
    echo "User $username already exists (id=$EXISTING), skipping"
    continue
  fi
  
  # Create user using the correct API endpoint
  USER_PAYLOAD=$(cat <<EOF
{
  "name": "$first_name $last_name",
  "email": "$email",
  "login": "$username",
  "password": "$password"
}
EOF
)
  
  echo "Creating user with payload: $USER_PAYLOAD"
  
  CREATE_RESP=$(curl -sf -X POST \
    -u "$ADMIN_USER:$ADMIN_PASSWORD" \
    -H "Content-Type: application/json" \
    "$GRAFANA_URL/api/admin/users" \
    -d "$USER_PAYLOAD" || true)
  
  echo "Create response: $CREATE_RESP"
  
  USER_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')
  if [ -z "$USER_ID" ]; then
    echo "WARNING: Failed to create user $username"
    echo "Response: $CREATE_RESP"
    continue
  fi
  
  echo "User $username created with ID: $USER_ID"
  
  # Set user role in organization (if not Admin)
  if [ "$role" != "Admin" ]; then
    ROLE_PAYLOAD=$(cat <<EOF
{
  "role": "$role"
}
EOF
)
    
    echo "Setting role $role for user $username (ID: $USER_ID)"
    ROLE_RESP=$(curl -sf -X PATCH \
      -u "$ADMIN_USER:$ADMIN_PASSWORD" \
      -H "Content-Type: application/json" \
      "$GRAFANA_URL/api/orgs/1/users/$USER_ID" \
      -d "$ROLE_PAYLOAD" || echo "failed")
      
    if [ "$ROLE_RESP" = "failed" ]; then
      echo "WARNING: Failed to set role for user $username"
    else
      echo "Role set successfully for user $username"
    fi
  fi
  
  echo "User $username created successfully"
done

echo "All users created successfully"
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [null_resource.grafana_admin_setup]
}
