# terraform-multi-env-eks

You're now getting a **file permission error** on `terraform.tfstate`, because **you previously ran Terraform with `sudo`**, which made the `terraform.tfstate` file owned by `root`.

---

## 🔍 The Problem

Terraform now runs **without `sudo`** (which is good), but it can’t access the `.tfstate` file because it’s owned by `root`.

```bash
open terraform.tfstate: permission denied
```

---

## ✅ Fix: Change Ownership of the Terraform Directory

Run the following to fix the file permissions:

```bash
sudo chown -R $USER:$USER .
```

This command:

* Recursively (`-R`) changes ownership of all files in the current directory (`.`)
* Sets the current user (`$USER`) as the owner

---

### ✅ Then Retry:

```bash
terraform plan
```

This should now work normally.

---

## 🛑 Avoid This in the Future:

Never run Terraform with `sudo`. It causes permission and credential issues.

Let me know if you'd like to add remote state storage (e.g., Terraform Cloud or S3) to avoid this issue permanently.
---

Your issue is due to the combination of **running Terraform with `sudo`** and **exporting AWS credentials without `sudo`**.

When you run:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

You're setting **environment variables for your current user**, but when you run:

```bash
sudo terraform plan
```

You're executing Terraform as **root**, which **does not inherit your environment variables** — so it cannot see the AWS credentials.

---

## ✅ Fix: Use Terraform Without `sudo`

Simply run:

```bash
terraform plan
```

Instead of:

```bash
sudo terraform plan
```

This ensures Terraform runs **as your current user**, who already has the AWS credentials set.

---

## 🧠 Why You Should Avoid `sudo` with Terraform

* Terraform does **not require root privileges** to run.
* Using `sudo` breaks environment-based workflows like AWS CLI profiles, exported variables, and credentials file detection.

---

## ✅ Optional: If You *Must* Use `sudo` (not recommended)

You’d need to explicitly pass environment variables through `sudo`, like:

```bash
sudo AWS_ACCESS_KEY_ID=AKIA... AWS_SECRET_ACCESS_KEY=... terraform plan
```

But again, the best practice is: **don’t use `sudo` with Terraform.**

---

Try it now with just:

```bash
terraform plan
```

Let me know if it works!

