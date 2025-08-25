###############################################################################
# Terraform ClickHouse cluster with modular S3 storage and backup capabilities
###############################################################################

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.4.0"
    }
  }
}

# --- Providers ---
provider "docker" {}

provider "docker" {
  alias = "remote_host"
  host  = var.storage_type == "local_ssd" ? "unix:///var/run/docker.sock" : "ssh://${var.remote_ssh_user}@${var.remote_host_name}"
}

provider "aws" {
  alias      = "remote_backup"
  access_key = var.minio_root_user
  secret_key = var.minio_root_password
  region     = "us-east-1"
  endpoints {
    s3 = "http://${var.remote_host_name}:${var.remote_minio_port}"
  }
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

provider "aws" {
  alias      = "local_storage"
  access_key = var.minio_root_user
  secret_key = var.minio_root_password
  region     = "us-east-1"
  endpoints {
    s3 = "http://localhost:${var.local_minio_port}"
  }
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# --- ClickHouse Cluster Module ---
module "clickhouse_cluster" {
  source = "./modules/clickhouse-cluster"

  providers = {
    docker.remote_host = docker.remote_host
    aws.remote_backup  = aws.remote_backup
    aws.local_storage  = aws.local_storage
  }

  # Base configuration
  clickhouse_base_path = var.clickhouse_base_path
  memory_limit         = var.memory_limit

  # Users
  super_user_name     = var.super_user_name
  bi_user_name        = var.bi_user_name
  super_user_password = var.super_user_password
  bi_user_password    = var.bi_user_password

  # Versions
  ch_version    = var.ch_version
  chk_version   = var.chk_version
  minio_version = var.minio_version

  # System
  ch_uid = var.ch_uid
  ch_gid = var.ch_gid

  # Ports
  use_standard_ports  = var.use_standard_ports
  ch_http_port        = var.ch_http_port
  ch_tcp_port         = var.ch_tcp_port
  ch_replication_port = var.ch_replication_port
  local_minio_port    = var.local_minio_port
  remote_minio_port   = var.remote_minio_port

  # MinIO and Storage
  minio_root_user     = var.minio_root_user
  minio_root_password = var.minio_root_password
  storage_type        = var.storage_type
  local_minio_path    = var.local_minio_path
  remote_minio_path   = var.remote_minio_path

  # SSH and Remote
  remote_ssh_user      = var.remote_ssh_user
  ssh_private_key_path = var.ssh_private_key_path
  remote_host_name     = var.remote_host_name

  # Buckets
  bucket_backup  = var.bucket_backup
  bucket_storage = var.bucket_storage

  # Hosts
  clickhouse_hosts = var.clickhouse_hosts

  # Feature flags
  enable_remote_backup = var.enable_remote_backup
}

# .env file
resource "null_resource" "mk_env_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.root}/env"
  }
}

resource "local_file" "env_file" {
  content    = <<EOT
CH_USER=${var.super_user_name}
CH_PASSWORD=${var.super_user_password}
BI_USER=${var.bi_user_name}
BI_PASSWORD=${var.bi_user_password}
MINIO_USER=${var.minio_root_user}
MINIO_PASSWORD=${var.minio_root_password}
EOT
  filename   = "${path.root}/env/clickhouse.env"
  depends_on = [null_resource.mk_env_dir]
}


# --- Monitoring Module ---
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  clickhouse_network_name = module.clickhouse_cluster.network_name
  clickhouse_network_id   = module.clickhouse_cluster.network_id
  clickhouse_uri          = "http://${module.clickhouse_cluster.clickhouse_nodes[0].name}:${module.clickhouse_cluster.clickhouse_nodes[0].http_port}"
  clickhouse_user         = var.super_user_name
  clickhouse_password     = var.super_user_password

  # Grafana admin configuration with fallback to super_user credentials
  grafana_admin_username = var.grafana_admin_username != "" ? var.grafana_admin_username : var.super_user_name
  grafana_admin_password = var.grafana_admin_password != "" ? var.grafana_admin_password : var.super_user_password
  grafana_admin_email    = var.grafana_admin_email != "" ? var.grafana_admin_email : "${var.super_user_name}@monitoring.local"

  # Create additional users only, admin is handled by container env vars
  grafana_local_users = [
    {
      username   = "analytics"
      password   = var.grafana_admin_password != "" ? var.grafana_admin_password : var.super_user_password
      first_name = "Analytics"
      last_name  = "User"
      email      = "analytics@monitoring.local"
      role       = "Editor"
    }
  ]
  clickhouse_hosts     = [for node in module.clickhouse_cluster.clickhouse_nodes : "${node.name}:${node.http_port}"]
  clickhouse_base_path = var.clickhouse_base_path
}
