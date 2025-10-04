[English](./README.md) | [한국어](./README.ko.md) | [日本語](./README.ja.md)

---

# EKSクラスターおよびアプリケーションスタックのデプロイ自動化 (Terraform & Ansible)

## 1. 概要

このプロジェクトは、AWS EKSクラスターとその上で動作するアプリケーションスタック全体を、IaC (Infrastructure as Code) の原則に従ってデプロイおよび管理します。

既存のシェルスクリプトベースのデプロイ方法をリファクタリングし、AWSインフラのプロビジョニングは**Terraform**で、Kubernetesクラスターの設定およびアプリケーションのデプロイは**Ansible**で役割を明確に分離しました。これにより、デプロイプロセス全体の自動化レベル、安定性、再利用性を向上させました。

- **Terraform (`terraform/`):** VPC、サブネット、EKSクラスター、ノードグループ、EFS、IAMロールおよびポリシー、クラスターアドオン（ALB Controller、CSI Drivers）など、すべてのAWSリソースを管理します。
- **Ansible (`ansible/`):** TerraformでプロビジョニングされたEKSクラスター上に、アプリケーション（Zookeeper、Kafka、データベース、監視スタック、Redmineなど）をロールベースで体系的にデプロイします。

## 2. 事前要件

このプロジェクトを実行するためには、ローカルマシンに次のツールがインストールおよび設定されている必要があります。

- **Terraform** (v1.0以上を推奨)
- **Ansible** (v2.10以上を推奨)
  - `community.kubernetes`コレクションのインストール: `ansible-galaxy collection install community.kubernetes`
- **AWS CLI**
  - AWS認証情報（アクセスキー、シークレットキー）が設定されている必要があります。(`aws configure`)
- **kubectl**
- **Helm** (v3.0以上を推奨)
  - Prometheus監視スタックのデプロイに必要です。

### ⚠️ セキュリティ設定 (重要!)

デプロイする前に、必ず**[SECURITY.md](SECURITY.md)**ドキュメントを参照して環境変数を設定してください。

## 3. デプロイ手順

デプロイは2つの段階で進行します。まずTerraformでAWSインフラを生成し、その後Ansibleでそのインフラ上にアプリケーションをデプロイします。

### 第1段階: TerraformによるAWSインフラのデプロイ

1.  **Terraformの作業ディレクトリに移動します。**

    ```bash
    cd terraform
    ```

2.  **Terraformを初期化します。**

    ```bash
    terraform init
    ```

3.  **Terraformの計画を確認し、インフラをデプロイします。**
    `apply`コマンドを実行すると、作成されるリソースのリストが表示されます。`yes`を入力してデプロイを進行します。

    ```bash
    terraform apply
    ```

    このプロセスは、EKSクラスターの作成により約15〜20分かかる場合があります。

4.  **デプロイ完了後、出力(Output)値を確認します。**
    デプロイが正常に完了すると、`outputs.tf`に定義された値（VPC ID、Subnet ID、EFS IDなど）が画面に出力されます。これらの値は次のAnsible段階で使用されます。

5.  **Kubeconfigの設定:**
    `apply`が完了した後、次のコマンドを実行して、ローカルの`kubectl`がEKSクラスターと通信できるように設定します。Terraformの出力値を確認して、正確なクラスター名とリージョンを入力してください。
    ```bash
    aws eks update-kubeconfig --region <aws_region> --name <cluster_name>
    ```

### 第2段階: Ansibleによるアプリケーションのデプロイ

1.  **Terraformの出力値をファイルに保存します。**
    Ansibleで変数として使用するため、`terraform`ディレクトリで次のコマンドを実行して出力値をJSONファイルに保存します。

    ```bash
    # (現在位置: terraform/)
    terraform output -json > ../ansible/terraform_outputs.json
    ```

2.  **Ansibleの作業ディレクトリに移動します。**

    ```bash
    # (現在位置: terraform/)
    cd ../ansible
    ```

3.  **Ansibleプレイブックを実行してアプリケーションをデプロイします。**
    `--extra-vars`オプションを使用して、先ほど作成したJSONファイルの内容を変数として渡します。
    ```bash
    # (現在位置: ansible/)
    ansible-playbook playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```
    プレイブックが実行されると、`csi-drivers`ロールから`ingress`ロールまで、定義された順序ですべてのアプリケーションがクラスターにデプロイされます。

### 特定のアプリケーションのみをデプロイ

特定のタグを使用して、個別のアプリケーションのみをデプロイできます。

```bash
# 高可用性Redisクラスターのみをデプロイ
ansible-playbook playbook.yml --tags "redis" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 高可用性Elasticsearchクラスターのみをデプロイ
ansible-playbook playbook.yml --tags "elasticsearch" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# Prometheus監視スタックのみをデプロイ
ansible-playbook playbook.yml --tags "prometheus" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# KafkaとZookeeperのみをデプロイ
ansible-playbook playbook.yml --tags "kafka,zookeeper" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass

# 分析スタック (Elasticsearch + Kibana) を一緒にデプロイ
ansible-playbook playbook.yml --tags "elasticsearch,kibana" --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
```

## 4. リソース削除手順

作成されたすべてのリソースを削除するには、デプロイの逆の順序で進行します。

1.  **Ansibleでアプリケーションを削除:**

    ```bash
    ansible-playbook delete_playbook.yml --extra-vars "@terraform_outputs.json" --vault-password-file .vault_pass
    ```

2.  **Terraformでインフラ全体を削除:**
    `terraform`ディレクトリで`destroy`コマンドを実行すると、VPCからEKSクラスターまですべてのAWSリソースが削除されます。エンドポイントターゲットのネットワーク接続も解除されます。
    ec2 -> ボリュームも削除、VPCが削除されない場合は手動で削除。
    ```bash
    cd refactored/terraform
    terraform destroy
    ```
    `yes`を入力して削除を進行します。

## 5. デプロイされるアプリケーションスタック

アプリケーションは`ansible/playbook.yml`を介して次の順序でデプロイされます。

### 🏗️ **インフラレイヤー**

1.  **CSI Drivers**: EFSおよびEBSボリュームのサポート
2.  **ALB Controller**: AWS Application Load Balancerの管理
3.  **Storage**: StorageClassおよびPersistentVolumeの設定

### 🌐 **ネットワーキングレイヤー**

4.  **Ingress**: ALBベースの外部/内部ロードバランサーの設定

### 💾 **データレイヤー**

5.  **Zookeeper**: 分散システムコーディネーション
6.  **Kafka**: リアルタイムストリーミングプラットフォーム (+Kafka UI)
7.  **PostgreSQL**: リレーショナルデータベース (Airflow用)

### ⚙️ **処理レイヤー**

8.  **Airflow**: ワークフローオーケストレーション (カスタムDAGを含む)
9.  **Adminer**: データベース管理ツール

### 🚀 **キャッシングレイヤー** (高可用性)

10. **Redis HA Cluster**: 高可用性インメモリキャッシュ
    - **Redis Master**: メインキャッシュサーバー (ng-masterノード)
    - **Redis Replicas**: 2つのレプリカ (ng-data1, ng-data2ノード)
    - **Redis Sentinels**: 3つの監視ノード (自動フェイルオーバー, Quorum=2)

### 📊 **分析レイヤー** (高可用性)

11. **Elasticsearch HA Cluster**: 高可用性検索および分析エンジン
    - **Elasticsearch Master**: クラスター管理 + データ保存 (ng-masterノード)
    - **Elasticsearch Data1**: データノード (ng-data1ノード)
    - **Elasticsearch Data2**: データノード (ng-data2ノード)
    - **シャード分散**: プライマリおよびレプリカシャードの自動分散による高可用性の保証
12. **Kibana**: データ視覚化ツール
13. **Elastic-HQ**: Elasticsearchクラスター管理

### 📈 **監視レイヤー** (Helmチャート)

14. **Prometheus Stack**: Helmを使用して統合デプロイ
    - **Prometheus**: メトリック収集と保存
    - **Grafana**: ダッシュボードと視覚化
    - **AlertManager**: アラート管理
    - 名前空間: `dev-system`
    - ServiceMonitorを介した既存サービスのメトリック収集

### 🔧 **管理レイヤー**

15. **Portainer**: Docker/Kubernetes管理インターフェース

### 🗄️ **追加データベース**

16. **MySQL**: 汎用リレーショナルデータベース

### 📋 **アプリケーション**

17. **Redmine**: プロジェクト管理ツール

### 🧪 **開発およびテスト**

18. **Zipkin**: 分散トレーシングシステム
19. **Load Testing**: パフォーマンステストツール

### 📝 **監視アクセス情報**

- **Grafana**: ALB Internal Ingressを介してアクセス可能
- **Prometheus**: `http://monitoring-kube-prometheus-prometheus.dev-system:9090`
- **AlertManager**: `http://monitoring-kube-prometheus-alertmanager.dev-system:9093`

## 6. プロジェクト構造

- **`terraform/`**: すべてのAWSインフラ(VPC, EKS, EFS, IAM, Addons)の定義

  - `main.tf`: エントリポイントとプロバイダー設定
  - `vpc.tf`: VPCとネットワークインフラ (10.0.0.0/16, 3 AZ)
  - `eks_cluster.tf`: EKSクラスターとIAMロール
  - `efs.tf`: EFSファイルシステム + アプリケーションごとのアクセスポイント
  - `variables.tf`: 設定変数 (AWSアカウント, リージョン, クラスター名)
  - `outputs.tf`: Ansibleに渡す出力値

- **`ansible/`**: すべてのKubernetesリソース(アプリケーション)のデプロイ定義

  - `inventory/`: Ansibleが対象とするサーバーリスト (現在は`localhost`)
  - `roles/`: 各アプリケーションごとに分離されたロールディレクトリ (19の役割)
  - `playbook.yml`: ロール実行順序を定義するメインプレイブック
  - `terraform_outputs.json`: Terraformから生成された出力値が保存されるファイル (Gitに含めないことを推奨)
  - `group_vars/all/`: グローバル変数とVaultの設定

- **`scripts/`**: ユーティリティスクリプト
