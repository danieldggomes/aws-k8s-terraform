variable "aws_region" {
  description = "aws Region"
}

variable "ami_id" {
  default = "ami-053b0d53c279acc90" # Ubuntu 22.04 LTS (us-east-1)
}

variable "instance_type" {
  default = "t3.medium"
}

variable "key_pair_name" {
  description = "IDs dos security groups que permitem acesso SSH e portas do Kubernetes"
}


