variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

variable "instance_count" {
  default = 2
}

variable "docker_image" {
  default = "nginx:1.11.5-alpine"
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

resource "aws_key_pair" "kp" {
  key_name   = "test-keypair"
  public_key = "${file(var.ssh_public_key)}"
}

data "template_file" "web_cloud_config" {
  template = "${file("${path.module}/web_cloud_config.yml.tpl")}"

  vars {
    web_name     = "nginx"
    docker_image = "${var.docker_image}"
    http_port    = 8080
  }
}

resource "aws_instance" "instance" {
  count             = "${var.instance_count}"
  availability_zone = "${data.aws_availability_zones.available.names[0]}"
  ami               = "${data.aws_ami.coreos.image_id}"
  instance_type     = "t2.micro"
  security_groups   = ["${aws_security_group.web.name}"]
  key_name          = "${aws_key_pair.kp.key_name}"
  user_data         = "${data.template_file.web_cloud_config.rendered}"
}

resource "aws_security_group" "web" {
  name = "web"

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = ["${aws_security_group.weblb.id}"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "weblb" {
  name = "allow_http"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "weblb" {
  security_groups    = ["${aws_security_group.weblb.id}"]
  instances          = ["${aws_instance.instance.*.id}"]
  availability_zones = ["${data.aws_availability_zones.available.names[0]}"]

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
}

output "elb_dns_name" {
  value = "${aws_elb.weblb.dns_name}"
}
