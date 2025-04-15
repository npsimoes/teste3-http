provider "tls" {}




###PARA TESTES - PARA DEPOIS APAGAR 
# 1 - Definir Nome da Chave SSH
variable "key_name" {
  description = "Nome do par de chaves SSH"
  default     = "id_rsa"
}

# 2 - Criar Key Pair na AWS usando chave pública existente
resource "aws_key_pair" "key_pair_ssh" {
  key_name   = var.key_name
  public_key = file("./devops.pub")  # A chave pública (formato OpenSSH)
}

# 3 - Usar a chave privada local existente (sem gerar)
output "private_key" {
  value       = file("./devops.pem") # A chave privada PEM existente
  sensitive   = true
}

####APAGAR DA PARTE DE CIMA





#chave possa ser usada no workflow do Ansible
#######
resource "aws_s3_object" "private_key" {
  bucket = "meu-bucket-terraform-github-actions-uc-20"
  key    = "outputs/id_rsa.pem"
  content = tls_private_key.rsa_4096.private_key_pem
  acl = "private"
  server_side_encryption = "AES256"
}

output "s3_private_key_path" {
  value = "s3://${aws_s3_object.private_key.bucket}/${aws_s3_object.private_key.key}"
  description = "Caminho do ficheiro da chave privada no S3"
  
}









# 5 - Security Group do Load Balancer (Público)
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security Group para Load Balancer"
  vpc_id      = aws_vpc.vpc.id

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

# 6 - Security Group para Web Servers (Privados)
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Security Group para Web Servers"
  vpc_id      = aws_vpc.vpc.id

  
    ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # SSH somente pelo Bastion - ver depois
  }
  
    
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Apenas trafego vindo do Load Balancer
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Criar Certificado Autoassinado no Terraform
resource "tls_private_key" "alb_ssl_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb_ssl_cert" {
  private_key_pem = tls_private_key.alb_ssl_key.private_key_pem

  subject {
    common_name  = aws_lb.app_lb.dns_name  # Usa o DNS do ALB como CN
    organization = "MyOrg"
  }

  validity_period_hours = 8760  # 1 ano
  is_ca_certificate     = false

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}


#Criar Certificado no IAM

resource "aws_iam_server_certificate" "alb_ssl_cert" {
  name             = "alb-ssl-cert"
  certificate_body = tls_self_signed_cert.alb_ssl_cert.cert_pem
  private_key      = tls_private_key.alb_ssl_key.private_key_pem
}





# 8 - Criar Load Balancer (HTTPS)
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

# 9 - Criar Target Group para as instancias Web
resource "aws_lb_target_group" "alb_ec2_tg" {
  name     = "web-server-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}

# 10 - Criar Listener HTTP
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_iam_server_certificate.alb_ssl_cert.arn  # Usa IAM, nao ACM!

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_ec2_tg.arn
  }
}


# 11 - Criar Auto Scaling Group com Web Servers
resource "aws_launch_template" "ec2_launch_template" {
  name = "web-server"

  image_id      = "ami-04b4f1a9cf54c11d0"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key_pair_ssh.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
    subnet_id                   = aws_subnet.private_subnet_1.id
  }

  user_data = base64encode(<<-EOF
  #!/bin/bash

  mkdir -p /home/ubuntu/.ssh
  chmod 700 /home/ubuntu/.ssh

  # Adicionar a chave pública ao authorized_keys
 echo "${file("./devops.pub")}" > /home/ubuntu/.ssh/authorized_keys
  chmod 600 /home/ubuntu/.ssh/authorized_keys
  chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys

  # Guardar a chave privada (não recomendado em produção!)
echo "${base64decode(filebase64("./devops.pem"))}" > /home/ubuntu/devops.pem
chmod 600 /home/ubuntu/devops.pem
chown ubuntu:ubuntu /home/ubuntu/devops.pem

  EOF
  )
}

resource "aws_autoscaling_group" "ec2_asg" {
  name                = "web-server-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 3
  target_group_arns   = [aws_lb_target_group.alb_ec2_tg.arn]
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  launch_template {
    id      = aws_launch_template.ec2_launch_template.id
    version = "$Latest"
  }


  tag {
    key                 = "Name"
    value               = "ec2-web-server"
    propagate_at_launch = true  # ✅ Garante que a tag será aplicada em cada instância criada
  }


}

# 12 - Coletar instâncias criadas no Auto Scaling Group
data "aws_instances" "web_instances" {
  depends_on = [aws_autoscaling_group.ec2_asg]  # 🚀 Garante que o Auto Scaling já criou as instâncias!

  filter {
    name   = "tag:Name"
    values = ["ec2-web-server"]
  }
}


# para ser usado no ansible

output "vpc_id" {
  value = aws_vpc.vpc.id
}


output "subnet_id" {
  value = aws_subnet.public_subnet_1.id
}

output "key_pair_name" {
  value = aws_key_pair.key_pair_ssh.key_name
}

output "private_key_pem" {
  value     = tls_private_key.rsa_4096.private_key_pem
  sensitive = true
}

######


output "alb_dns_name" {
  value = aws_lb.app_lb.dns_name
}

output "ec2_private_ips" {
  value = data.aws_instances.web_instances.private_ips
}



####mandar os dados dos ips para o s3
# Criar o ficheiro inventory localmente na instância Ansible
# Criar o ficheiro inventory localmente
resource "local_file" "ansible_inventory" {
  content = <<EOT
[webservers]
%{for ip in data.aws_instances.web_instances.private_ips ~}
${ip} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_rsa_aux.pem
%{endfor~}
EOT

  filename        = "${path.module}/inventory"
  file_permission = "0644"
}



# Fazer upload do ficheiro inventory para o S3
# Fazer upload do ficheiro inventory para o S3
resource "aws_s3_object" "inventory_file" {
  bucket  = "meu-bucket-terraform-github-actions-uc-20"
  key     = "outputs/inventory"
  source  = local_file.ansible_inventory.filename  # 📂 Usa o ficheiro criado localmente
  acl     = "private"
  server_side_encryption = "AES256"

  depends_on = [local_file.ansible_inventory]  # ⚠️ Garante que o inventory foi criado antes do upload
}

# Output do caminho do ficheiro no S3 - INVENTRORY
output "s3_inventory_path" {
  value       = "s3://${aws_s3_object.inventory_file.bucket}/${aws_s3_object.inventory_file.key}"
  description = "Caminho do ficheiro inventory no S3 - QUERO VER ESTE FICHEIRO"
}


output "debug_private_ips" {
  value = data.aws_instances.web_instances.private_ips
}

