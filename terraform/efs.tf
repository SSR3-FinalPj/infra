############################################
# efs.tf
############################################

# 1. EFS 파일 시스템 생성
resource "aws_efs_file_system" "main" {
  tags = {
    Name = "${var.cluster_name}-efs"
  }
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
}

# 2. EFS 마운트 타겟 생성
# 기존 스크립트가 모든 서브넷에 마운트 타겟을 생성하므로, public과 private 서브넷을 합쳐서 반복 처리합니다.
resource "aws_efs_mount_target" "main" {
  for_each = merge(aws_subnet.public, aws_subnet.private)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}

# 3. EFS Access Point 설정 정의
locals {
  access_points = {
    "fsap-mysql" = {
      path = "/mysql",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-kafka" = {
      path = "/kafka",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-redis-master" = {
      path = "/redis-master",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-redis-replica1" = {
      path = "/redis-replica1",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-redis-replica2" = {
      path = "/redis-replica2",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-es-master-config" = {
      path = "/es-master/config",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-master-data" = {
      path = "/es-master/data",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-master-logs" = {
      path = "/es-master/logs",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data1-config" = {
      path = "/es-data1/config",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data1-data" = {
      path = "/es-data1/data",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data1-logs" = {
      path = "/es-data1/logs",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data2-config" = {
      path = "/es-data2/config",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data2-data" = {
      path = "/es-data2/data",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-es-data2-logs" = {
      path = "/es-data2/logs",
      uid = 1000, gid = 1000, perms = "0755"
    },
    "fsap-kibana-config" = {
      path = "/kibana/config",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-kibana-data" = {
      path = "/kibana/data",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-postgres-data" = {
      path = "/postgres/data",
      uid = 0, gid = 0, perms = "0755"
    },
    "fsap-airflow-dags" = {
      path = "/airflow-dags",
      uid = 1000, gid = 1000, perms = "0755"
    }
  }
}

# 4. EFS Access Point 생성
resource "aws_efs_access_point" "main" {
  for_each = local.access_points

  file_system_id = aws_efs_file_system.main.id
  
  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = each.value.path
    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = each.value.perms
    }
  }

  tags = {
    Name = each.key
  }
}
