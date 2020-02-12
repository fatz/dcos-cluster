provider "aws" {}

// if availability zones is not set request the available in this region
data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

#
resource "aws_vpc" "dcos_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name" = "existingvpc"
  }
}

# Create private Subnets
resource "aws_subnet" "dcos_subnet" {
  vpc_id            = "${aws_vpc.dcos_vpc.id}"
  count             = "${length(data.aws_availability_zones.available.names)}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  cidr_block              = "${cidrsubnet("192.168.0.0/16", 8, count.index)}"
  map_public_ip_on_launch = false

  tags = {
    "Usage"   = "dcos"
    "Nettype" = "private"
    "Naam"    = "dcos-20"
  }
}

resource "aws_subnet" "jumphost_subnet" {
  vpc_id            = "${aws_vpc.dcos_vpc.id}"
  availability_zone = "${element(data.aws_availability_zones.available.names, 1)}"

  cidr_block              = "192.168.255.0/28"
  map_public_ip_on_launch = true

  tags = {
    "Usage"   = "jumphost"
    "Nettype" = "private"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.dcos_vpc.id}"
  count             = "${length(data.aws_availability_zones.available.names)}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"

  cidr_block              = "${cidrsubnet("192.168.0.0/16", 8, count.index + 20)}"
  map_public_ip_on_launch = false

  tags = {
    "Usage"   = "dcos"
    "Nettype" = "public"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.dcos_vpc.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.dcos_vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

##### NAT Gateway #######
resource "aws_eip" "nat" {
  count = "${length(data.aws_availability_zones.available.names)}"
  vpc   = true
}

resource "aws_nat_gateway" "gw" {
  count         = "${length(data.aws_availability_zones.available.names)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.public.*.id,count.index)}"
}

resource "aws_route_table" "dcos_subnet" {
  count  = "${length(data.aws_availability_zones.available.names)}"
  vpc_id = "${aws_vpc.dcos_vpc.id}"
}

resource "aws_route" "route" {
  count                  = "${length(data.aws_availability_zones.available.names)}"
  route_table_id         = "${element(aws_route_table.dcos_subnet.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.gw.*.id, count.index)}"
}

resource "aws_route_table_association" "dcos_subnet" {
  count          = "${length(data.aws_availability_zones.available.names)}"
  subnet_id      = "${element(aws_subnet.dcos_subnet.*.id,count.index)}"
  route_table_id = "${element(aws_route_table.dcos_subnet.*.id, count.index)}"
}

###### JUMPHOST #######
resource "aws_iam_role" "jumphost" {
  name = "existingvpc-jumphost-${data.aws_region.current.name}-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "jumphost-ec2" {
  role       = "${aws_iam_role.jumphost.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "jumphost-vpc" {
  role       = "${aws_iam_role.jumphost.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "jumphost-iam-ro" {
  role       = "${aws_iam_role.jumphost.name}"
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

resource "aws_iam_policy" "jumphost-additionals" {
  name        = "dcos-jumphost-additionals"
  path        = "/"
  description = "My test policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "iam:UploadServerCertificate",
        "iam:CreateRole",
        "iam:CreateInstanceProfile",
        "iam:PutRolePolicy",
        "iam:AddRoleToInstanceProfile",
        "iam:PassRole",
        "iam:DeleteRolePolicy",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:DeleteServerCertificate",
        "iam:DeleteRole"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "jumphost-additionals" {
  role       = "${aws_iam_role.jumphost.name}"
  policy_arn = "${aws_iam_policy.jumphost-additionals.arn}"
}

resource "aws_iam_instance_profile" "jumphost" {
  name = "mwt-jumphost-${data.aws_region.current.name}-profile"
  role = "${aws_iam_role.jumphost.name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "jumphost" {
  name        = "jumphost-${data.aws_region.current.name}"
  description = "Allow jumphost traffic"
  vpc_id      = "${aws_vpc.dcos_vpc.id}"
}

resource "aws_security_group_rule" "jumphost_ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.jumphost.id}"
}

resource "aws_security_group_rule" "jumphost_egress" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.jumphost.id}"
}

data "aws_ami" "centos" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS ENA 1804*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"] # Canonical
}

resource "aws_key_pair" "jumphost" {
  key_name   = "cops5813-jumphost-key"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

resource "aws_instance" "jumphost" {
  ami           = "${data.aws_ami.centos.id}"
  instance_type = "m5.large"

  root_block_device {
    volume_type = "gp2"
    volume_size = "50"
  }

  key_name = "${aws_key_pair.jumphost.key_name}"

  subnet_id                   = "${aws_subnet.jumphost_subnet.id}"
  iam_instance_profile        = "${aws_iam_instance_profile.jumphost.name}"
  associate_public_ip_address = true
  vpc_security_group_ids      = ["${aws_security_group.jumphost.id}"]
}

resource "tls_private_key" "jumphost" {
  algorithm = "RSA"
}

resource "null_resource" "run_ansible_from_bootstrap_node_to_install_dcos" {
  # triggers {}

  connection {
    host = "${aws_instance.jumphost.public_ip}"
    user = "centos"
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "centos"
    }

    inline = [
      "sudo yum install -y epel-release",
      "sudo yum install -y jq python36 awscli screen git zip unzip",
      "mkdir -p ~/.aws",
      "git clone https://github.com/tfutils/tfenv.git ~/.tfenv",
      "sudo ln -s ~/.tfenv/bin/* /usr/local/bin",
      "tfenv install 0.11.14",
      "tfenv use 0.11.14",
      "sudo curl https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.13/dcos -o /usr/local/bin/dcos",
      "sudo chmod +x /usr/local/bin/dcos",
      "mkdir -p ~/existingvpc",
      "mkdir -p ~/.ssh",
    ]
  }

  provisioner "file" {
    destination = "/home/centos/.ssh/id_rsa"
    content     = "${tls_private_key.jumphost.private_key_pem}"
  }

  provisioner "file" {
    destination = "/home/centos/.ssh/id_rsa.pub"
    content     = "${tls_private_key.jumphost.public_key_openssh}"
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "centos"
    }

    inline = [
      "chmod 600 ~/.ssh/id_rsa",
    ]
  }

  provisioner "file" {
    destination = "/home/centos/.aws/config"
    content     = "${file("${path.module}/aws.ini")}"
  }

  provisioner "file" {
    destination = "/home/centos/existingvpc/main.tf"
    content     = "${file("${path.module}/../main.tf")}"
  }

  provisioner "file" {
    destination = "/home/centos/existingvpc/variables.tf"
    content     = "${file("${path.module}/../variables.tf")}"
  }

  provisioner "file" {
    destination = "/home/centos/existingvpc/terraform.tfvars"
    content     = "${file("${path.module}/../terraform.tfvars")}"
  }
}

output "jumphost" {
  value = "${aws_instance.jumphost.public_ip}"
}

output "vpc_id" {
  value = "${aws_vpc.dcos_vpc.id}"
}

output "public_key" {
  value = "${tls_private_key.jumphost.public_key_openssh}"
}
