output "cluster_name" { value = aws_ecs_cluster.this.name }
output "load_balancer_dns_name" { value = aws_lb.this.dns_name }
output "load_balancer_zone_id" { value = aws_lb.this.zone_id }
output "service_names" {
  value = {
    dcc                = aws_ecs_service.dcc.name
    ecommerce_frontend = aws_ecs_service.ecommerce_frontend.name
    ecommerce_backend  = aws_ecs_service.ecommerce_backend.name
  }
}
output "task_definition_arns" {
  value = {
    dcc                = aws_ecs_task_definition.dcc.arn
    ecommerce_frontend = aws_ecs_task_definition.ecommerce_frontend.arn
    ecommerce_backend  = aws_ecs_task_definition.ecommerce_backend.arn
  }
}
