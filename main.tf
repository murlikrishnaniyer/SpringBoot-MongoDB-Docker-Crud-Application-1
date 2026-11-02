terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-2" # Change to your preferred region
}

# ==============================================================================
# 1. NETWORK SETUP (VPC, Subnets)
# ==============================================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-2a"
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-2b"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

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
resource "aws_security_group" "spring_sg" {
  name        = "spring-app-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow traffic out to Mongo and inbound to app"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to public for testing
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mongo_sg" {
  name        = "mongo-db-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow inbound from Spring App SG only"

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
}

# ==============================================================================
# 3. ECS CLUSTER & SERVICE CONNECT NAMESPACE
# ==============================================================================
resource "aws_service_discovery_http_namespace" "ecs_namespace" {
  name        = "apps.local"
  description = "Service Connect Namespace"
}

resource "aws_ecs_cluster" "main" {
  name = "fargate-cluster"
}

# IAM Role for Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_task_execution_role_unique"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Ensure the execution role has the explicit policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Add a direct policy rule for log creation assurance
resource "aws_iam_role_policy" "ecs_cw_policy" {
  name = "ecs-cw-logs-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}


# ==============================================================================
# 4. MONGO SERVICE DEFINITION
# ==============================================================================
resource "aws_ecs_task_definition" "mongo" {
  family                   = "mongo-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "mongodb"
    image     = "docker.io/library/mongo:latest"
    essential = true
    portMappings = [{
      name          = "mongo-port"
      containerPort = 27017
      hostPort      = 27017
      protocol      = "tcp"
    }]
  }])
}

resource "aws_ecs_service" "mongo" {
  name            = "mongo-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mongo.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.mongo_sg.id]
    assign_public_ip = true # Required if pulling from Docker Hub without NAT Gateways
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs_namespace.arn
    service {
      port_name      = "mongo-port"
      discovery_name = "mongo" # This creates the DNS record -> mongo.apps.local
      client_alias {
        port = 27017
      }
    }
  }
}

# ==============================================================================
# 5. SPRING BOOT SERVICE DEFINITION
# ==============================================================================
resource "aws_ecs_task_definition" "spring" {
  family                   = "spring-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "spring-app"
    image     = "docker.io/tekpie/springboot-mongodb-docker-crud-application-app" # <-- Ensure your image name is correct
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
        value = "mongo.apps.local"
      },
      {
        name  = "SPRING_DATA_MONGODB_PORT"
        value = "27017"
      },
      # === ADD THIS TO FORCE LOG FLUSHING ===
      {
        name  = "JAVA_TOOL_OPTIONS"
        value = "-Dlogging.channels.stdout.buffered=false -Dfile.encoding=UTF-8"
      }
    ]

    # === ADD/VERIFY THIS BLOCK ===
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/spring-app"
        "awslogs-region"        = "ap-south-2" # <-- MUST match your deployment region exactly
        "awslogs-stream-prefix" = "spring"
      }
    }
  }])
}

resource "aws_ecs_service" "spring" {
  name            = "spring-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.spring.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.spring_sg.id]
    assign_public_ip = true
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs_namespace.arn
  }

  # THIS BLOCK WAS MISSING OR COMMENTED OUT
  load_balancer {
    target_group_arn = aws_lb_target_group.spring_tg.arn
    container_name   = "spring-app" # Must match the name inside container_definitions
    container_port   = 8080
  }


  # Ensure MongoDB is deployed first so the app can resolve the endpoint
  depends_on = [aws_ecs_service.mongo]
}

# ==============================================================================
# 6. APPLICATION LOAD BALANCER (ALB) SETUP
# ==============================================================================
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  vpc_id      = aws_vpc.main.id
  description = "Allow public HTTP traffic to ALB"

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

resource "aws_lb" "app_alb" {
  name               = "spring-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "spring_tg" {
  name        = "spring-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for Fargate awsvpc mode

  health_check {
    path                = "/actuator/health" # Spring Boot Actuator default (or use "/" if not installed)
    port                = "8080"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
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
# 7. LOGS FOR METRICS & TROUBLESHOOTING
# ==============================================================================
resource "aws_cloudwatch_log_group" "spring_logs" {
  name              = "/ecs/spring-app"
  retention_in_days = 7
}

resource "aws_iam_role_policy_attachment" "ecs_logging" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# ==============================================================================
# MODIFICATIONS TO EXISTING RESOURCES (Update your previous definitions with these)
# ==============================================================================

# UPDATE: Modify spring_sg to only accept traffic coming directly from the ALB
resource "aws_security_group_rule" "allow_alb_to_spring" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.spring_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

# UPDATE: Add the logConfiguration block inside your Spring target definition container_definitions
# Modify the JSON encoded section in aws_ecs_task_definition.spring to look like this:
/*
  container_definitions = jsonencode([{
    name      = "spring-app"
    image     = "docker.io/yourusername/your-spring-app:latest"
    essential = true
    portMappings = [{
      name          = "spring-port"
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]
    environment = [
      {
        name  = "SPRING_DATA_MONGODB_URI"
        value = "mongodb://mongo.apps.local:27017/your_db"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/spring-app"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "spring"
      }
    }
  }])
*/

# UPDATE: Link the ALB target group to your Spring ECS service
# Modify your aws_ecs_service.spring resource block by adding this block inside it:
/*
  load_balancer {
    target_group_arn = aws_lb_target_group.spring_tg.arn
    container_name   = "spring-app"
    container_port   = 8080
  }
*/

# ==============================================================================
# 8. OUTPUTS
# ==============================================================================
output "alb_dns_name" {
  value       = aws_lb.app_alb.dns_name
  description = "The public URL to test your live APIs"
}
