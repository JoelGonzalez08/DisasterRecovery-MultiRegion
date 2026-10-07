output "alb_dns_name" {
  description = "Nombre DNS público del Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN del Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_zone_id" {
  description = "Canonical Hosted Zone ID del ALB (requerido para registros Route 53 en Fase 3)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN del Target Group"
  value       = aws_lb_target_group.app.arn
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group (requerido por failover_trigger.py en Fase 3)"
  value       = aws_autoscaling_group.this.name
}

output "alb_security_group_id" {
  description = "ID del Security Group del ALB"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "ID del Security Group de las instancias EC2"
  value       = aws_security_group.ec2.id
}
