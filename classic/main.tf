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

module "web" {
  source = "./modules/web"
}

output "elb_dns_name" {
  value = "${module.web.elb_dns_name}"
}
