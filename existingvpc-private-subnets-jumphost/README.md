# managed VPC with Jumphost and non public ip dcos
In this scenario we have a managed vpc with private and public subnets. The private subnets get internet access via NAT gateways.

## VPC module
the vpc module provides private and public subnets for every AZ. It places NAT gateways for every Subnet into the AZs public network. It adds a route table pointing to the Nat gateway for each private network.

### JUMP HOST
Furthermore it spawns a Jumphost with instance profile and prepared SSH key.

### applying
```
export AWS_REGION=us-east-1
$ cd vpc; terraform apply --auto-aprove

Outputs:

jumphost = 1.2.3.4
public_key = ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQChlrUTxDDxvw8xRRZs8oAdMwvYaB3RRNxJPaHT8H8W0XuMewAEsGc5lh3tOdz2x2zAJ8/ZVnIQt8CJM3nS8wa59HJbJZTyEYcIx+5Nk/EwYBNJM22RsAUGB5xsTgt+6GzUy13/ec8NwSUTxtYYLIkYxiUe7WufEbpHldAKbDNfHngB0aDWYb5VQVufppDU14JoQjIiK4QFqC8hgSZPUMecY4hgbZxh8B3ERm74m/FrGqmz+UIuTmx5Vvyc/Dgg2TA6OKiBGp1PDgF0sJ/8Sy5iYvXk2ZR4s5TQeR19DJgmBDPWIu6v3Uud3sb4WFyslBs53X+vYN7qRdVzzSwi1p6j

vpc_id = vpc-EXAMPLE952417af942
```


## After spawning the VPC:
We expect your ssh key to acces the jump host is available in your ssh-agent:

```
ssh centos@$(cd vpc; terraform output jumphost)

$ cd private-poc
$ eval "$(ssh-agent -s)"
$ ssh-add
$ terraform apply
```

terraform will ask you about the vpc_id which you got from the vpc module.

### ENTERPRISE
For DC/OS Enterprise you need to put your license key into `terraform.tfvars`. Please edit that file on the jump host adding your license key. ( Keep in mind that .tfvars only supports plain text no interpolation or functions)
