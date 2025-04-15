

#vem do arquivo ec2.tf
variable "vpc_id" {}

variable "key_pair_name" {}


variable "subnet_id" {}

variable "private_key_pem" {}


######



# 7 - Criar Bastion Host (server_ansible) para acessar as máquinas privadas
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Security Group para Bastion Host"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Substituir pelo seu IP público
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🚀 Baixar a chave privada do S3 para um ficheiro auxiliar **ANTES DA INSTÂNCIA**
resource "null_resource" "fetch_private_key" {
  provisioner "local-exec" {
    command = <<EOT
      echo "📥 Baixando chave privada do S3..."
      aws s3 cp s3://meu-bucket-terraform-github-actions-uc-20/outputs/id_rsa.pem ${path.module}/id_rsa_aux.pem --region us-east-1
      chmod 600 ${path.module}/id_rsa_aux.pem
      echo "✅ Chave privada salva no ficheiro auxiliar!"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

# 🚀 Baixar o ficheiro inventory do S3 para um ficheiro auxiliar **ANTES DA INSTÂNCIA**
resource "null_resource" "fetch_inventory" {
  provisioner "local-exec" {
    command = <<EOT
      echo "📥 Baixando ficheiro inventory do S3..."
      aws s3 cp s3://meu-bucket-terraform-github-actions-uc-20/outputs/inventory ${path.module}/inventory_aux --region us-east-1
      chmod 644 ${path.module}/inventory_aux
      echo "✅ Inventory salvo no ficheiro auxiliar!"
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}



# 🚨 Criar a instância **SOMENTE DEPOIS** da chave ter sido baixada
resource "aws_instance" "server_ansible" {
  ami                         = "ami-04b4f1a9cf54c11d0"
  instance_type               = "t2.micro"
  key_name                    = var.key_pair_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  depends_on = [null_resource.fetch_private_key] # ⚠️ Garante que a chave foi criada antes da instância

  # 📂 Copiar a chave privada auxiliar para a instância
  provisioner "file" {
    source      = file("./devops.pem")
    destination = "/home/ubuntu/.ssh/id_rsa_aux.pem"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")  # ✅ Usa a chave passada como variável
      host        = self.public_ip
    }
  }

  # 🔧 Aplicar permissões ao ficheiro dentro da instância
  provisioner "remote-exec" {
    inline = [
      "echo '🔄 Criando ficheiro vazio para chave privada...'",
      "mkdir -p /home/ubuntu/.ssh",
      "touch /home/ubuntu/.ssh/id_rsa_aux.pem",
      "chmod 600 /home/ubuntu/.ssh/id_rsa_aux.pem",
      "chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa_aux.pem",
      "echo '✅ Ficheiro criado e pronto para receber a chave!'",
      "ls -lah /home/ubuntu/.ssh/"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")  # ✅ Usa a chave correta para SSH
      host        = self.public_ip
    }
  }

  # resto das coissa para correr o ansible

  # Copiar os ficheiros necessários
  provisioner "file" {
    source      = "./playbook.yml"
    destination = "/home/ubuntu/playbook.yml"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")
      host        = self.public_ip
    }
  }

provisioner "file" {
    source      = "./ansible.cfg"
    destination = "/home/ubuntu/ansible.cfg"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")
      host        = self.public_ip
    }
  }

  # 📂 Copiar o ficheiro inventory auxiliar para a instância Ansible
provisioner "file" {
  source      = "${path.module}/inventory_aux"
  destination = "/home/ubuntu/inventory"

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("./devops.pem")
    host        = self.public_ip
  }
}

# 🔧 Aplicar permissões ao ficheiro dentro da instância
provisioner "remote-exec" {
  inline = [
    "echo '🔄 Criando ficheiro vazio para inventory...'",
    "touch /home/ubuntu/inventory",
    "chmod 644 /home/ubuntu/inventory",
    "chown ubuntu:ubuntu /home/ubuntu/inventory",
    "echo '✅ Inventory configurado com sucesso!'",
    "ls -lah /home/ubuntu/"
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.private_key_pem
    host        = self.public_ip
  }
}



  provisioner "file" {
    source      = "./index.html"
    destination = "/home/ubuntu/index.html"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")
      host        = self.public_ip
    }
  }


  # Instalar Ansible e rodar o playbook
  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/devops.pem",
      "sudo apt-get update",
      "sudo apt-get install -y ansible",
      "ANSIBLE_CONFIG=/home/ubuntu/ansible.cfg ansible-playbook -i /home/ubuntu/inventory /home/ubuntu/playbook.yml"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops.pem")
      host        = self.public_ip
    }
  }










  tags = {
    Name = "server_ansible"
  }
}

# 📤 Outputs para debug
output "bastion_public_ip" {
  value = aws_instance.server_ansible.public_ip
}

output "debug_private_key_pem" {
  value     = var.private_key_pem
  sensitive = true
}

output "debug_private_key_pem_base64" {
  value     = base64encode(var.private_key_pem)
  sensitive = true
}
