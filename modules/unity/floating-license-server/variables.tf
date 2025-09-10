####################################################
# General Configuration
####################################################

variable "name" {
  type        = string
  description = "The name applied to resources in the Unity Floating License Server module."
  default     = "unity-floating-license-server"
}

variable "tags" {
  type        = map(any)
  description = "Tags to apply to resources created by this module."
  default = {
    "iac-management" = "CGD-Toolkit"
    "iac-module"     = "UnityFloatingLicenseServer"
    "iac-provider"   = "Terraform"
    "environment"    = "Dev"
  }
}

####################################################
# Networking
####################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC in which the Unity Floating License Server will be deployed."
}

variable "vpc_subnet" {
  type        = string
  description = "The subnet where the EC2 instance running the Unity Floating License Server will be deployed."
}

variable "existing_eni_id" {
  type        = string
  default     = "eni-06266d5820d250fb9" #null
  description = "ID of an existing Elastic Network Interface (ENI) to use for the EC2 instance running the Unity Floating License Server, as its registration will be binded to it. If not provided, a new ENI will be created."
}

variable "add_eni_public_ip" {
  type        = bool
  default     = true
  description = "If true and \"existing_eni_id\" is not provided, an Elastic IP (EIP) will be created and associated with the newly created Elastic Network Interface (ENI) to be used with the Unity Floating License Server. If \"existing_eni_id\" is provided, this variable is ignored and no new EIP will be added to the provided ENI."
}

#############################################################
# Unity Floating License Server EC2 Instance Configuration
#############################################################

variable "unity_license_server_instance_ami_id" {
  type        = string
  description = "The AMI ID to use in the EC2 instance running the Unity Floating License Server. Defaults to the Ubuntu Server 24.04 LTS (HVM) AMI ID. Note that this option is provided to specify newer versions of the Ubuntu AMI only."
  default     = "ami-0d1b5a8c13042c939"
}

variable "unity_license_server_instance_type" {
  type        = string
  description = "The instance type to use for the Unity Floating License Server. Defaults to t3.small."
  default     = "t3.small"
}

variable "unity_license_server_instance_ebs_size" {
  type        = string
  default     = "20"
  description = "The size of the EBS volume in GB."
}

variable "enable_instance_detailed_monitoring" {
  type        = bool
  default     = false
  description = "Enables detailed monitoring for the instance by increasing the frequency of metric collection from 5-minute intervals to 1-minute intervalss in CloudWatch to provide more granular data. Note this will result in increased cost."
}

####################################################
# Unity Floating License Server Configuration
####################################################

variable "unity_license_server_file_path" {
  type        = string
  description = "Local path to the Linux version of the Unity Floating License Server zip file."
}

variable "unity_license_server_bucket_name" {
  type        = string
  description = "Name of the Unity Floating License Server-specific S3 bucket to create."
  default     = "unity-license-server-"
}

variable "unity_license_server_admin_password_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the Unity Floating License Server admin dashboard password. Password must be the only value and stored as text, not as key/value JSON. If not passed, one will be created randomly. Password must be between 8-12 characters."
  type        = string
  default     = null
}

variable "unity_license_server_name" {
  type        = string
  description = "Name of the Unity Floating License Server."
  default     = "UnityLicenseServer"
}

variable "unity_license_server_port" {
  type        = string
  description = "Port the Unity Floating License Server will listing on (between 1025 and 65535). Defaults to 8080."
  default     = "8080"
}
