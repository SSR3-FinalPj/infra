[English](./SECURITY.md) | [한국어](./SECURITY.ko.md) | [日本語](./SECURITY.ja.md)

---

# Security Configuration Guide

This document explains how to securely manage sensitive project information using **Ansible Vault** and **Terraform tfvars**.

## 🔒 Security Principles

1.  **Never commit sensitive information to Git.**
2.  **Use encrypted security management with Ansible Vault.**
3.  **Use separate configuration files for each environment.**
4.  **Adhere to industry best practices.**

## 📁 File Structure

```
refactored/
├── .gitignore                           # Exclude sensitive files
├── terraform/
│   ├── terraform.tfvars                 # Terraform actual values (Git excluded)
│   └── terraform.tfvars.example         # Terraform template (Git included)
└── ansible/
    ├── .vault_pass                      # Vault password file (Git excluded)
    └── group_vars/all/
        ├── vars.yml                     # Publicly available variables (Git included)
        ├── vault.yml                    # Encrypted sensitive information (Git included)
        └── vault.yml.example            # Vault template (Git included)
```

## 🚀 Initial Setup

### Step 1: Terraform Configuration

```bash
# Navigate to the Terraform directory
cd terraform

# Copy the template file
cp terraform.tfvars.example terraform.tfvars

# Modify with actual values
vi terraform.tfvars
```

**Values to modify in `terraform.tfvars`:**

- `YOUR_AWS_ACCOUNT_ID`: Your actual AWS Account ID (12 digits)
- `YOUR_USERNAME`: Your actual IAM username

### Step 2: Ansible Vault Configuration

```bash
# Navigate to the Ansible directory
cd ansible

# Create the Vault password file
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass

# Set up the Vault file
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vi group_vars/all/vault.yml

# Encrypt the Vault file (Important!)
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass
```

**Values to modify in `group_vars/all/vault.yml`:**

- Change all passwords to strong passwords.
- Replace API keys with your actual issued keys.
- It is essential to replace with actual values before encryption!

## 🔐 How to Use Ansible Vault (Advanced)

### Encrypting a Vault File

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### Editing a Vault File

```bash
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Running a Playbook with Vault

```bash
# Password prompt method
ansible-playbook playbook.yml --ask-vault-pass --extra-vars "@terraform_outputs.json"

# Using a password file (Recommended)
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"

# Running a specific role only
ansible-playbook playbook.yml --tags "airflow" --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

## 🛠️ Deployment Workflow

### Full Deployment

```bash
# 1. Deploy infrastructure with Terraform
cd terraform
terraform init
terraform apply

# 2. Save Terraform output
terraform output -json > ../ansible/terraform_outputs.json

# 3. Deploy applications with Ansible (using Vault)
cd ../ansible
ansible-playbook playbook.yml --vault-password-file .vault_pass --extra-vars "@terraform_outputs.json"
```

### Variable Priority

Ansible reads variables in the following order of precedence:

1.  **Environment Variables** (`.env` file): `lookup('env', 'VARIABLE_NAME')`
2.  **Vault Variables** (encrypted values): `vault_variable_name`
3.  **Default Value**: None (will cause an error)

## ⚠️ Important Notes

### DO ✅

- Commit template files (`.example`) to Git.
- Use strong passwords (at least 12 characters, including special characters).
- Change passwords regularly.
- In production, use services like AWS Secrets Manager or HashiCorp Vault.

### DON'T ❌

- Commit actual configuration files (`.tfvars`, `.env`) to Git.
- Use weak passwords ('example', 'password123', etc.).
- Hardcode actual API keys in code or documents.
- Share sensitive information via Slack/email with team members.

## 🔍 Pre-Commit Checklist

Before committing, be sure to check the following:

```bash
# Check if sensitive files are excluded
git status

# Check if .gitignore is working correctly
git check-ignore terraform/terraform.tfvars
git check-ignore ansible/.env

# Check for any files containing sensitive information
git diff --cached | grep -E "(password|secret|key|token|arn:aws:iam::[0-9]+)"
```

## 🆘 Troubleshooting

### Problem: Terraform errors out with missing variable values.

**Solution**: Ensure the `terraform.tfvars` file exists and all required variables are set.

### Problem: Ansible cannot find a variable.

**Solution**: Check if the `.env` file is in the `ansible/` directory and that the variable name is correct.

### Problem: API key is not working.

**Solution**:

1.  Verify that the API key is valid.
2.  Ensure the API key has the appropriate permissions.
3.  Check for any rate limiting or quota restrictions.

## 📞 Support

If you encounter problems, check the following:

1.  Have you completed all the setup steps in this document?
2.  Are sensitive files excluded in `.gitignore`?
3.  Is the syntax of your environment variable file correct?

---

**⚠️ Important**: The security of this project is the user's responsibility. Please pay special attention to managing sensitive information!
