output "udf_files" {
  value = fileset("${path.module}/${var.udf_dir}", "*.py")
}