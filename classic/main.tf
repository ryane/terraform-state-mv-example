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

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "coreos" {
  most_recent = true
  owners      = ["595879546273"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["CoreOS-stable-*"]
  }
}

module "app" {
  source = "./modules/app"
  ssh_public_key = "${var.ssh_public_key}"
  instance_count = 2
  availability_zone = "${data.aws_availability_zones.available.names[0]}"
  ami               = "${data.aws_ami.coreos.image_id}"
}

output "elb_dns_name" {
  value = "${module.app.elb_dns_name}"
}
