output "vpc_id" {
  description = "Identificador único de la VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "Bloque CIDR de la VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Lista de IDs de las subredes públicas (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Lista de IDs de las subredes privadas de aplicación (EC2 ASG)"
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "Lista de IDs de las subredes privadas de datos (RDS MySQL)"
  value       = aws_subnet.private_data[*].id
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway para conectividad saliente"
  value       = aws_nat_gateway.nat.id
}
