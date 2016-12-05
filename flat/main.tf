variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "name" {
  default = "terraform-state-mv-example"
}

variable "env" {
  default = "staging"
}

variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

provider "aws" {
  region  = "${var.region}"
  profile = "multi-tier-rails"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name        = "vpc-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name        = "ig-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "${cidrsubnet(var.vpc_cidr, 8, 1)}"
  map_public_ip_on_launch = true

  tags {
    Name        = "public-subnet-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name        = "public-route-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_route" "public_gateway_route" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "applb" {
  name   = "applb"
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "sg-applb-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name   = "app"
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = ["${aws_security_group.applb.id}"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "sg-app-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
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

data "template_file" "app_cloud_config" {
  template = "${file("${path.module}/app_cloud_config.yml.tpl")}"

  vars {
    app_name     = "nginx"
    docker_image = "nginx:1.11.5-alpine"
    http_port    = 8080
  }
}

resource "aws_key_pair" "kp" {
  key_name   = "keypair-${var.env}-${var.name}"
  public_key = "${file(var.ssh_public_key)}"
}

resource "aws_launch_configuration" "app" {
  name_prefix     = "app-${var.env}-${var.name}-"
  image_id        = "${data.aws_ami.coreos.image_id}"
  instance_type   = "t2.micro"
  user_data       = "${data.template_file.app_cloud_config.rendered}"
  key_name        = "${aws_key_pair.kp.key_name}"
  security_groups = ["${aws_security_group.app.id}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cluster" {
  launch_configuration = "${aws_launch_configuration.app.name}"
  vpc_zone_identifier  = ["${aws_subnet.public.id}"]
  load_balancers       = ["${aws_elb.applb.name}"]
  min_size             = 2
  max_size             = 5

  tag {
    key                 = "Name"
    value               = "app-asg-${var.env}-${var.name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Infra"
    value               = "${var.name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Env"
    value               = "${var.env}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Terraformed"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "applb" {
  subnets = ["${aws_subnet.public.id}"]

  security_groups = ["${aws_security_group.applb.id}"]
  internal        = false

  listener {
    instance_port     = 8080
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    target              = "HTTP:8080/"
    interval            = 5
  }

  tags {
    Name        = "elb-applb-${var.env}-${var.name}"
    Infra       = "${var.name}"
    Environment = "${var.env}"
    Terraformed = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
}
