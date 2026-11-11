terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state (recommended for production)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "springboot-mongodb-crud/terraform.tfstate"
  #   region         = "ap-south-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# ==============================================================================
# 1. NETWORK SETUP (VPC, Subnets, IGW)
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

# Public Subnet 1
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-1"
  }
}

# Public Subnet 2
resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "a1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "a2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ==============================================================================
# 2. SECURITY GROUPS
# ==============================================================================

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-alb-sg"
  description = "Allow public HTTP/HTTPS traffic to ALB"
  vpc_id      = aws_vpc.main.id

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

  tags = {
    Name = "${var.app_name}-alb-sg"
  }
}

# Spring App Security Group
resource "aws_security_group" "spring_sg" {
  name        = "${var.app_name}-spring-sg"
  description = "Security group for Spring Boot application"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-spring-sg"
  }
}

# Allow ALB to Spring App
resource "aws_security_group_rule" "allow_alb_to_spring" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.spring_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

# MongoDB Security Group
resource "aws_security_group" "mongo_sg" {
  name        = "${var.app_name}-mongo-sg"
  description = "Allow inbound from Spring App SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.spring_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-mongo-sg"
  }
}

# ==============================================================================
# 3. IAM ROLES & POLICIES
# ==============================================================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.app_name}-ecs-execution-role"
  }
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch Logs policy
resource "aws_iam_role_policy" "ecs_cw_policy" {
  name = "${var.app_name}-ecs-cw-logs-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# 4. ECS CLUSTER & SERVICE CONNECT NAMESPACE
# ==============================================================================

# Service Discovery Namespace
resource "aws_service_discovery_http_namespace" "ecs_namespace" {
  name        = "${var.app_name}.local"
  description = "Service Connect Namespace for ${var.app_name}"

  tags = {
    Name = "${var.app_name}-namespace"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.app_name}-cluster"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ==============================================================================
# 5. CLOUDWATCH LOGS
# ==============================================================================

resource "aws_cloudwatch_log_group" "spring_logs" {
  name              = "/ecs/spring-app"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.app_name}-spring-logs"
  }
}

resource "aws_cloudwatch_log_group" "mongo_logs" {
  name              = "/ecs/mongo"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.app_name}-mongo-logs"
  }
}

# ==============================================================================
# 6. MONGODB TASK DEFINITION & SERVICE
# ==============================================================================

resource "aws_ecs_task_definition" "mongo" {
  family                   = "${var.app_name}-mongo-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.mongo_cpu
  memory                   = var.mongo_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "mongodb"
    image     = "mongo:7.0"
    essential = true
    portMappings = [{
      name          = "mongo-port"
      containerPort = 27017
      hostPort      = 27017
      protocol      = "tcp"
    }]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.mongo_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "mongo"
      }
    }

    mountPoints = []
  }])

  tags = {
    Name = "${var.app_name}-mongo-task"
  }
}

resource "aws_ecs_service" "mongo" {
  name                 = "${var.app_name}-mongo-service"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.mongo.arn
  desired_count        = var.mongo_desired_count
  launch_type          = "FARGATE"
  force_new_deployment = false

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.mongo_sg.id]
    assign_public_ip = true
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs_namespace.arn
    service {
      port_name      = "mongo-port"
      discovery_name = "mongo"
      client_alias {
        port = 27017
      }
    }
  }

  tags = {
    Name = "${var.app_name}-mongo-service"
  }

  depends_on = [aws_iam_role_policy.ecs_cw_policy]
}

# ==============================================================================
# 7. SPRING BOOT TASK DEFINITION & SERVICE
# ==============================================================================

resource "aws_ecs_task_definition" "spring" {
  family                   = "${var.app_name}-spring-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.spring_cpu
  memory                   = var.spring_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "spring-app"
    image     = "${var.docker_image_url}:${var.docker_image_tag}"
    essential = true
    
    portMappings = [{
      name          = "spring-port"
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "SPRING_DATA_MONGODB_HOST"
        value = "mongo.${aws_service_discovery_http_namespace.ecs_namespace.name}"
      },
      {
        name  = "SPRING_DATA_MONGODB_PORT"
        value = "27017"
      },
      {
        name  = "SPRING_DATA_MONGODB_DATABASE"
        value = "BookStore"
      },
      {
        name  = "JAVA_TOOL_OPTIONS"
        value = "-Dlogging.channels.stdout.buffered=false -Dfile.encoding=UTF-8 -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
      },
      {
        name  = "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE"
        value = "health,metrics,info"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.spring_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "spring"
      }
    }
  }])

  tags = {
    Name = "${var.app_name}-spring-task"
  }
}

resource "aws_ecs_service" "spring" {
  name                 = "${var.app_name}-spring-service"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.spring.arn
  desired_count        = var.spring_desired_count
  launch_type          = "FARGATE"
  force_new_deployment = false

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.spring_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.spring_tg.arn
    container_name   = "spring-app"
    container_port   = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs_namespace.arn
  }

  tags = {
    Name = "${var.app_name}-spring-service"
  }

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_service.mongo,
    aws_iam_role_policy.ecs_cw_policy
  ]
}

# ==============================================================================
# 8. APPLICATION LOAD BALANCER (ALB)
# ==============================================================================

resource "aws_lb" "app_alb" {
  name               = "sbt-crud-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false

  tags = {
    Name = "${var.app_name}-alb"
  }
}

resource "aws_lb_target_group" "spring_tg" {
  name        = "sbt-spring-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/actuator/health"
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.app_name}-spring-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring_tg.arn
  }
}

# ==============================================================================
# 9. AUTO-SCALING (Optional)
# ==============================================================================

resource "aws_appautoscaling_target" "spring_target" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id       = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.spring.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "spring_cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.app_name}-spring-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.spring_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.spring_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.spring_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "spring_memory" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.app_name}-spring-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.spring_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.spring_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.spring_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 80.0
  }
}
