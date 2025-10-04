[English](./SECURITY.md) | [한국어](./SECURITY.ko.md) | [日本語](./SECURITY.ja.md)

---

# セキュリティ設定ガイド (Security Configuration Guide)

このドキュメントは、プロジェクトの機密情報を**Ansible Vault**と**Terraform tfvars**を使用して安全に管理する方法を説明します。

## 🔒 セキュリティ原則

1.  **機密情報は絶対にGitにコミットしない**
2.  **Ansible Vaultで暗号化されたセキュリティ管理を使用する**
3.  **環境ごとに分離された設定ファイルを使用する**
4.  **実務のベストプラクティスを遵守する**

## 📁 ファイル構造

```
refactored/
├── .gitignore                           # 機密ファイルを除外
├── terraform/
│   ├── terraform.tfvars                 # Terraformの実際の値 (Git除外)
│   └── terraform.tfvars.example         # Terraformのテンプレート (Gitに含める)
└── ansible/
    ├── .vault_pass                      # Vaultパスワードファイル (Git除外)
    └── group_vars/all/
        ├── vars.yml                     # 公開可能な変数 (Gitに含める)
        ├── vault.yml                    # 暗号化された機密情報 (Gitに含める)
        └── vault.yml.example            # Vaultテンプレート (Gitに含める)
```

## 🚀 初期設定

### 第1段階: Terraformの設定

```bash
# Terraformディレクトリに移動
cd terraform

# テンプレートファイルをコピー
cp terraform.tfvars.example terraform.tfvars

# 実際の値に修正
vi terraform.tfvars
```

**`terraform.tfvars`で修正すべき値:**

- `YOUR_AWS_ACCOUNT_ID`: 実際のAWSアカウントID (12桁)
- `YOUR_USERNAME`: 実際のIAMユーザー名

### 第2段階: Ansible Vaultの設定

```bash
# Ansibleディレクトリに移動
cd ansible

# Vaultパスワードファイルを作成
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass

# Vaultファイルを設定
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vi group_vars/all/vault.yml

# Vaultファイルを暗号化 (重要!)
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass
```

**`group_vars/all/vault.yml`で修正すべき値:**

- すべてのパスワードを強力なパスワードに変更
- APIキーを実際に発行されたキーに置き換え
- 暗号化する前に実際の値に置き換えることが必須！

## 🔐 Ansible Vaultの使い方 (高度)

### Vaultファイルの暗号化

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### Vaultファイルの編集

```bash
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Vaultと共にプレイブックを実行

```bash
# パスワードプロンプト方式
ansible-playbook playbook.yml --ask-vault-pass --extra-vars "@terraform_outputs.json"

# パスワードファイルを使用 (推奨)
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"

# 特定のロールのみ実行
ansible-playbook playbook.yml --tags "airflow" --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

## 🛠️ デプロイワークフロー

### フルデプロイ

```bash
# 1. Terraformでインフラをデプロイ
cd terraform
terraform init
terraform apply

# 2. Terraformの出力値を保存
terraform output -json > ../ansible/terraform_outputs.json

# 3. Ansibleでアプリケーションをデプロイ (Vault使用)
cd ../ansible
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

### 変数の優先順位

Ansibleは次の優先順位で変数を読み込みます:

1.  **環境変数** (`.env` ファイル): `lookup('env', 'VARIABLE_NAME')`
2.  **Vault変数** (暗号化された値): `vault_variable_name`
3.  **デフォルト値**: なし (エラー発生)

## ⚠️ 注意事項

### DO ✅

- テンプレートファイル(`.example`)はGitにコミットする
- 強力なパスワードを使用する (最低12文字、特殊文字を含む)
- 定期的にパスワードを変更する
- 本番環境ではAWS Secrets ManagerやHashiCorp Vaultなどを使用する

### DON'T ❌

- 実際の設定ファイル(`.tfvars`, `.env`)をGitにコミットする
- 弱いパスワードを使用する ('example', 'password123' など)
- 実際のAPIキーをコードやドキュメントにハードコーディングする
- チームメンバー間でSlack/メールで機密情報を共有する

## 🔍 Gitコミット前のチェックリスト

コミットする前に必ず確認してください:

```bash
# 機密ファイルが除外されているか確認
git status

# .gitignoreが正しく機能しているか確認
git check-ignore terraform/terraform.tfvars
git check-ignore ansible/.env

# 機密情報が含まれるファイルがないか確認
git diff --cached | grep -E "(password|secret|key|token|arn:aws:iam::[0-9]+)"
```

## 🆘 トラブルシューティング

### 問題: Terraformで変数値がないというエラー

**解決策**: `terraform.tfvars`ファイルが存在し、必須変数が設定されているか確認

### 問題: Ansibleで変数が見つからない

**解決策**: `.env`ファイルが`ansible/`ディレクトリにあるか、変数名が正確か確認

### 問題: APIキーが機能しない

**解決策**:

1.  APIキーが有効か確認
2.  APIキーの権限が適切に設定されているか確認
3.  レートリミットやクォータ制限があるか確認

## 📞 サポート

問題が発生した場合は、以下を確認してください:

1.  このドキュメントの設定手順をすべて完了したか
2.  `.gitignore`で機密ファイルが除外されているか
3.  環境変数ファイルの構文が正しいか

---

**⚠️ 重要**: このプロジェクトのセキュリティはユーザーの責任です。機密情報の管理には特に注意してください！
