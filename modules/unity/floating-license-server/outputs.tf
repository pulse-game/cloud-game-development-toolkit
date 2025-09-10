output "eni_id" {
  description = "Elastic Network ID (ENI) used when binding the Unity Floating License Server.."
  value       = local.eni_id
}

output "instance_public_ip" {
  value = aws_instance.unity_license_server.public_ip
}

output "unity_license_server_s3_bucket" {
  description = "S3 bucket name used by the Unity License Server service."
  value       = aws_s3_bucket.unity_license_server_bucket.id
}

output "dashboard_password_secret_arn" {
  description = "ARN of the secret containing the dashboard password"
  value       = local.admin_password_arn
  depends_on  = [null_resource.wait_for_user_data]
}

output "registration_request_filename" {
  description = "Filename for the server registration request file"
  value       = "server-registration-request.xml"
}

output "registration_request_presigned_url" {
  description = "Presigned URL for downloading the server registration request file (valid for 1 hour)"
  value       = trimspace(data.local_file.registration_url.content)
}

output "services_config_filename" {
  description = "Filename for the services config file"
  value       = "services-config.json"
}

output "services_config_presigned_url" {
  description = "Presigned URL for downloading the services configuration file (valid for 1 hour)"
  value       = trimspace(data.local_file.config_url.content)
}
