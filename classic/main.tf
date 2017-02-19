variable "region" {
  default = "us-east-1"
}

variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

provider "aws" {
  region  = "${var.region}"
  profile = "multi-tier-rails"
}

module "app" {
  source = "./modules/app"
}

output "elb_dns_name" {
  value = "${module.app.elb_dns_name}"
}
