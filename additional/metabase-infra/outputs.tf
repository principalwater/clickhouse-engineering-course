output "metabase_url" {
  value = "http://localhost:${var.metabase_port}"
}

output "postgres_creds" {
  value = {
    user = var.pg_user
    db   = var.pg_db
    pass = var.pg_password
    host = "localhost"
    port = 5432
  }
  sensitive = true
}