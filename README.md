[English](./README.md) | [한국어](./README.ko.md) | [日本語](./README.ja.md)

---

# EKS Cluster and Application Stack Deployment Automation (Terraform & Ansible)

## 1. Overview

This project deploys and manages an AWS EKS cluster and the entire application stack running on it, following Infrastructure as Code (IaC) principles.

By refactoring the existing shell script-based deployment method, we have clearly separated roles: **Terraform** for AWS infrastructure provisioning and **Ansible** for Kubernetes cluster configuration and application deployment. This enhances the automation level, stability, and reusability of the entire deployment process.

- **Terraform (`terraform/`):** Manages all AWS resources, including VPC, Subnets, EKS Cluster, Node Groups, EFS, IAM Roles and Policies, and cluster add-ons (ALB Controller, CSI Drivers).
- **Ansible (`ansible/`):** Systematically deploys applications (Zookeeper, Kafka, Databases, Monitoring Stack, Redmine, etc.) in a role-based manner on the EKS cluster provisioned by Terraform.

## 2. Prerequisites

The following tools must be installed and configured on your local machine to run this project.

- **Terraform** (v1.0 or higher recommended)
- **Ansible** (v2.10 or higher recommended)
  - Install `community.kubernetes` collection: `ansible-galaxy collection install community.kubernetes`
- **AWS CLI**
  - AWS credentials (Access Key, Secret Key) must be configured. (`aws configure`)
- **kubectl**
- **Helm** (v3.0 or higher recommended)
  - Required for deploying the Prometheus monitoring stack.

### ⚠️ Security Settings (Important!)

Before deploying, you must refer to the **[SECURITY.md](SECURITY.md)** document to set environment variables.

## 3. Deployment Procedure

The deployment proceeds in two stages. First, create the AWS infrastructure with Terraform, then deploy the applications on that infrastructure with Ansible.

### Stage 1: Deploy AWS Infrastructure with Terraform

1.  **Navigate to the Terraform working directory.**

    ```bash
    cd terraform
    ```

2.  **Initialize Terraform.**

    ```bash
    terraform init
    ```

3.  **Review the Terraform plan and deploy the infrastructure.**
    Running the `apply` command will display a list of resources to be created. Enter `yes` to proceed with the deployment.

    ```bash
    terraform apply
    ```

    This process may take about 15-20 minutes due to EKS cluster creation.

4.  **Check the output values after deployment is complete.**
    Once deployment is successful, the values defined in `outputs.tf` (VPC ID, Subnet ID, EFS ID, etc.) will be displayed on the screen. These values will be used in the next Ansible stage.

5.  **Configure Kubeconfig:**
    After `apply` is complete, run the following command to configure your local `kubectl` to communicate with the EKS cluster. Check the Terraform output for the correct cluster name and region.
    ```bash
    aws eks update-kubeconfig --region <aws_region> --name <cluster_name>
    ```

### Stage 2: Deploy Applications with Ansible

1.  **Save Terraform output values to a file.**
    To use them as variables in Ansible, run the following command in the `terraform` directory to save the output values to a JSON file.

    ```bash
    # (Current location: terraform/)
    terraform output -json > ../ansible/terraform_outputs.json
    ```

2.  **Navigate to the Ansible working directory.**

    ```bash
    # (Current location: terraform/)
    cd ../ansible
    ```

3.  **Run the Ansible playbook to deploy the applications.**
    Use the `--extra-vars` option to pass the contents of the JSON file you just created as variables.
    ```bash
    # (Current location: ansible/)
    ansible-playbook playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```
    As the playbook runs, all applications will be deployed to the cluster in the order defined, from the `csi-drivers` role to the `ingress` role.

### Deploying Specific Applications Only

You can deploy individual applications using specific tags:

```bash
# Deploy only the high-availability Redis cluster
ansible-playbook playbook.yml --tags "redis" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Deploy only the high-availability Elasticsearch cluster
ansible-playbook playbook.yml --tags "elasticsearch" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Deploy only the Prometheus monitoring stack
ansible-playbook playbook.yml --tags "prometheus" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Deploy only Kafka and Zookeeper
ansible-playbook playbook.yml --tags "kafka,zookeeper" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Deploy the analysis stack (Elasticsearch + Kibana) together
ansible-playbook playbook.yml --tags "elasticsearch,kibana" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

## 4. Resource Deletion Procedure

To delete all created resources, proceed in the reverse order of deployment.

1.  **Delete applications with Ansible:**

    ```bash
    ansible-playbook delete_playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```

2.  **Delete the entire infrastructure with Terraform:**
    Running the `destroy` command in the `terraform` directory will delete all AWS resources from the VPC to the EKS cluster. It will also detach endpoint target network connections.
    ec2 -> also remove volumes, if VPC is not deleted, delete it manually.
    ```bash
    cd refactored/terraform
    terraform destroy
    ```
    Enter `yes` to proceed with the deletion.

## 5. Deployed Application Stack

Applications are deployed in the following order via `ansible/playbook.yml`:

### 🏗️ **Infrastructure Layer**

1.  **CSI Drivers**: EFS and EBS volume support
2.  **ALB Controller**: Manages AWS Application Load Balancer
3.  **Storage**: StorageClass and PersistentVolume setup

### 🌐 **Networking Layer**

4.  **Ingress**: External/Internal load balancer setup based on ALB

### 💾 **Data Layer**

5.  **Zookeeper**: Distributed system coordination
6.  **Kafka**: Real-time streaming platform (+Kafka UI)
7.  **PostgreSQL**: Relational database (for Airflow)

### ⚙️ **Processing Layer**

8.  **Airflow**: Workflow orchestration (including custom DAGs)
9.  **Adminer**: Database management tool

### 🚀 **Caching Layer** (High Availability)

10. **Redis HA Cluster**: High-availability in-memory cache
    - **Redis Master**: Main cache server (ng-master node)
    - **Redis Replicas**: 2 replicas (ng-data1, ng-data2 nodes)
    - **Redis Sentinels**: 3 monitoring nodes (automatic failover, Quorum=2)

### 📊 **Analysis Layer** (High Availability)

11. **Elasticsearch HA Cluster**: High-availability search and analysis engine
    - **Elasticsearch Master**: Cluster management + data storage (ng-master node)
    - **Elasticsearch Data1**: Data node (ng-data1 node)
    - **Elasticsearch Data2**: Data node (ng-data2 node)
    - **Shard Distribution**: High availability ensured by automatic distribution of primary and replica shards
12. **Kibana**: Data visualization tool
13. **Elastic-HQ**: Elasticsearch cluster management

### 📈 **Monitoring Layer** (Helm Chart)

14. **Prometheus Stack**: Integrated deployment using Helm
    - **Prometheus**: Metric collection and storage
    - **Grafana**: Dashboard and visualization
    - **AlertManager**: Alert management
    - Namespace: `dev-system`
    - Collects metrics from existing services via ServiceMonitor

### 🔧 **Management Layer**

15. **Portainer**: Docker/Kubernetes management interface

### 🗄️ **Additional Databases**

16. **MySQL**: General-purpose relational database

### 📋 **Applications**

17. **Redmine**: Project management tool

### 🧪 **Development and Testing**

18. **Zipkin**: Distributed tracing system
19. **Load Testing**: Performance testing tool

### 📝 **Monitoring Access Information**

- **Grafana**: Accessible via ALB Internal Ingress
- **Prometheus**: `http://monitoring-kube-prometheus-prometheus.dev-system:9090`
- **AlertManager**: `http://monitoring-kube-prometheus-alertmanager.dev-system:9093`

## 6. Project Structure

- **`terraform/`**: Defines all AWS infrastructure (VPC, EKS, EFS, IAM, Addons)

  - `main.tf`: Entry point and provider settings
  - `vpc.tf`: VPC and network infrastructure (10.0.0.0/16, 3 AZs)
  - `eks_cluster.tf`: EKS cluster and IAM roles
  - `efs.tf`: EFS file system + per-application Access Points
  - `variables.tf`: Configuration variables (AWS account, region, cluster name)
  - `outputs.tf`: Output values to be passed to Ansible

- **`ansible/`**: Defines deployment of all Kubernetes resources (applications)

  - `inventory/`: List of target servers for Ansible (currently `localhost`)
  - `roles/`: Role directories separated by application (19 roles)
  - `playbook.yml`: Main playbook defining the role execution order
  - `terraform_outputs.json`: File where outputs from Terraform are stored (recommended not to include in Git)
  - `group_vars/all/`: Global variables and Vault settings

- **`scripts/`**: Utility scripts
