variable "project_name" {
  description = "Prefix for resource names and the Project cost-allocation tag."
  type        = string
  default     = "claims-approval-api"
}

variable "aws_region" {
  description = "Region to deploy into."
  type        = string
  default     = "us-east-2"
}

# ---------- Network ----------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Subnets are carved out of it in network.tf."
  type        = string
  default     = "10.0.0.0/16"
}

# ---------- Application ----------

variable "image_tag" {
  description = "Tag of the image in ECR to run, normally the git commit SHA. Set by the deploy script."
  type        = string
}

variable "container_port" {
  description = "Port the Spring Boot app listens on inside the container."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU, the smallest size)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB. 1024 leaves headroom for the JVM; 512 is the minimum for 0.25 vCPU."
  type        = number
  default     = 1024

  validation {
    condition     = contains([512, 1024, 2048], var.task_memory)
    error_message = "With 0.25 vCPU, Fargate only allows 512, 1024 or 2048 MiB."
  }
}

variable "desired_count" {
  description = "Number of running tasks. 1 keeps cost minimal; set 0 to pause the app without destroying."
  type        = number
  default     = 1
}

variable "health_check_path" {
  description = "Path the ALB probes to decide whether a task is healthy."
  type        = string
  default     = "/actuator/health"
}

# ---------- Database ----------

variable "db_instance_class" {
  description = "RDS instance size. db.t4g.micro is the smallest current-generation class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GiB (gp3; 20 is the minimum)."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the application database."
  type        = string
  default     = "claims"
}

variable "db_username" {
  description = "Master username for RDS (the password is generated, never passed in)."
  type        = string
  default     = "claims_app"
}

# ---------- Observability ----------

variable "log_retention_days" {
  description = "How long CloudWatch keeps application logs. Short retention keeps storage cost near zero."
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Optional email for the 5xx alarm. Leave empty to create the alarm without a subscription."
  type        = string
  default     = ""
}
