# 1- criacao da vpc

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"


  tags = {
    Name = "minha-vpc"
  }
}



# 2 - Criação das subnets




# 2.1 - Criação da primeira subnet pública
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.vpc.id   # Associando a subnet ao VPC criado
  cidr_block        = "10.0.1.0/24"  # Definição do bloco CIDR
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"  # Definição da zona de disponibilidade
  
  tags = {
    Name = "Public Subnet 1"  # Nomeação da subnet pública
  }
}

# 2.2 - Criação da segunda subnet pública
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.vpc.id   # Associando a subnet ao VPC criado
  cidr_block        = "10.0.2.0/24"  # Definição do bloco CIDR
  map_public_ip_on_launch = true
  availability_zone = "us-east-1b"  # Definição da zona de disponibilidade
  
  tags = {
    Name = "Public Subnet 2"  # Nomeação da subnet pública
  }
}

# 2.3 - Criação da primeira subnet privada
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.vpc.id   # Associando a subnet ao VPC criado
  cidr_block        = "10.0.3.0/24"  # Definição do bloco CIDR
  availability_zone = "us-east-1a"  # Definição da zona de disponibilidade
  
  tags = {
    Name = "Private Subnet 1"  # Nomeação da subnet privada
  }
}

# 2.4 - Criação da segunda subnet privada
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.vpc.id   # Associando a subnet ao VPC criado
  cidr_block        = "10.0.4.0/24"  # Definição do bloco CIDR
  availability_zone = "us-east-1b"  # Definição da zona de disponibilidade
  
  tags = {
    Name = "Private Subnet 2"  # Nomeação da subnet privada
  }
}

# 2.5 - Internet Gateway, com ligação à VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id   # Associando o Internet Gateway à VPC
  
  tags = {
    Name = "minha-gw"  # Nomeação do Internet Gateway
  }
}

# 2.6 - Tabela de rotas para a subnet pública
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id   # Associando a tabela de rotas à VPC
  
  route {
    cidr_block = "0.0.0.0/0"  # Definição da rota padrão para saída para a internet
    gateway_id = aws_internet_gateway.gw.id  # Associando a rota ao Internet Gateway
  }
  
  tags = {
    Name = "Public Subnet Route Table"  # Nomeação da tabela de rotas públicas
  }
}

# 2.7 - Associação da tabela de rotas às subnets públicas
resource "aws_route_table_association" "public_subnet_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id  # Associação da primeira subnet pública
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id  # Associação da segunda subnet pública
  route_table_id = aws_route_table.public_route_table.id
}

# 2.8 - Elastic IP para NAT Gateway
resource "aws_eip" "eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]  # Garantindo que o Internet Gateway já foi criado
}

# 2.9 - NAT Gateway para permitir saída da subnet privada para a internet
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnet_1.id  # Associando à primeira subnet pública
  depends_on    = [aws_internet_gateway.gw]
  
  tags = {
    Name = "NAT Gateway"
  }
}

# 2.10 - Tabela de rotas para as subnets privadas
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  depends_on = [aws_nat_gateway.nat_gateway]
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id  # Associando à rota padrão do NAT Gateway
  }
  
  tags = {
    Name = "Private Subnet Route Table"
  }
}

# 2.11 - Associação da tabela de rotas às subnets privadas
resource "aws_route_table_association" "private_subnet_association_1" {
  subnet_id      = aws_subnet.private_subnet_1.id  # Associação da primeira subnet privada
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_association_2" {
  subnet_id      = aws_subnet.private_subnet_2.id  # Associação da segunda subnet privada
  route_table_id = aws_route_table.private_route_table.id
}




