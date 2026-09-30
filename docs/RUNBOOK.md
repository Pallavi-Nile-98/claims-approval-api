# Runbook: break-fix exercises

Five failures deliberately induced on the live AWS deployment, one at a time, then
diagnosed with real tools and fixed. Each entry follows the same shape:
**symptom -> diagnosis commands -> root cause -> fix -> prevention**.

Timestamps are from the actual session (local time, EDT). Outputs are trimmed but real.

## Environment notes (Windows)

These cost time during the exercises and are common in real support tickets:

- **`bash` in PowerShell is WSL, not Git Bash.** With no WSL distribution installed it fails with
  `execvpe(/bin/bash) failed`. Run scripts from the Git Bash window, or call
  `"C:\Program Files\Git\bin\bash.exe"` explicitly.
- **`curl` in Windows PowerShell 5.1 is an alias for `Invoke-WebRequest`.** Use `curl.exe`.
- **Git Bash rewrites arguments that look like paths.** `aws logs tail /ecs/claims-approval-api`
  fails with `Member must satisfy regular expression pattern` because the name became
  `C:/Program Files/Git/ecs/...`. Fix: `export MSYS_NO_PATHCONV=1` (the scripts already do).
- **The image tag must be the deployed one.** Terraform commands take `-var image_tag=...`;
  after a new commit, `git rev-parse HEAD` points at an image that was never pushed. Get the
  running tag with:
  `aws ecs describe-task-definition --task-definition claims-approval-api --query 'taskDefinition.containerDefinitions[0].image' --output text`

---

## 1. Database unreachable: app security group rule removed from the RDS security group

**Induced by** deleting the only inbound rule on the database security group, as a manual
console change would:

```bash
aws ec2 revoke-security-group-ingress --group-id <db-sg> --security-group-rule-ids <rule-id>
```

### Symptom

- **For about 25 minutes: nothing.** `scripts/verify.sh` passed 9/9 six minutes after the rule was gone.
- Then **502 Bad Gateway** on every request through the ALB, including `/actuator/health`.
- ECS kept starting tasks that never became healthy; the target group showed targets
  `unhealthy` / `draining`.

### Diagnosis

```bash
# 1. What is ECS doing? New tasks start and get registered, but no "steady state" follows.
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].events[:6].[createdAt,message]' --output text

# 2. Why did a task stop? The old, previously healthy task:
aws ecs describe-tasks --cluster claims-approval-api --tasks <task-id> \
  --query 'tasks[0].[lastStatus,stoppedReason]' --output text
#   STOPPED  Task failed ELB health checks in (target-group ...)

# 3. What is the app saying? Read the LAST "Caused by" first.
aws logs tail /ecs/claims-approval-api --since 5m --format short \
  | grep -iE 'error|exception|timeout|hikari|started'
#   Caused by: org.flywaydb...FlywaySqlException: Unable to obtain connection from database
#   Caused by: org.postgresql.util.PSQLException: The connection attempt failed.
#   Caused by: java.net.SocketTimeoutException: Connect timed out

# 4. Rule out DNS: the RDS endpoint still resolves, to a private IP.
nslookup <rds-endpoint>
#   Address: 10.0.11.110

# 5. Check the firewall in front of the database.
aws ec2 describe-security-groups --group-ids <db-sg> --query 'SecurityGroups[0].IpPermissions'
#   []

# 6. Ask Terraform what differs from the intended state (drift detection).
terraform -chdir=terraform plan -var image_tag=<deployed-tag>
#   Warning: AWS resource not found during refresh ... db_from_app
#   # aws_vpc_security_group_ingress_rule.db_from_app will be created
```

**Reading the error type matters most here:**

| Error | Meaning | Look at |
|---|---|---|
| `Connect timed out` | Packets silently dropped | Security group, NACL, routes |
| `Connection refused` | Host reachable, nothing listening | Port, DB down |
| `UnknownHostException` | Name did not resolve | DNS, typo in host |
| `password authentication failed` | Network fine | Credentials |

Security groups never reject, they **drop**, so a missing rule always shows up as a timeout.

### Root cause

The database security group's only inbound rule (TCP 5432 from the app security group) was
deleted, so every new connection from the app to RDS was silently dropped.

It stayed hidden because **security groups are stateful**: connections that are already open
are tracked and keep working after a rule is removed, and HikariCP reuses its pooled
connections. The outage appeared when new connections were needed:

| Time | Event |
|---|---|
| 21:04:49 | Rule deleted |
| 21:10 | `verify.sh` 9/9 PASS (existing pooled connections) |
| 21:11 | New deployment forced; new tasks fail with `Connect timed out` and crash-loop |
| ~21:25-21:31 | HikariCP retires connections after `maxLifetime` (30 min); replacements fail, `/actuator/health` reports the DB as DOWN |
| 21:32:19 | ECS stops the old task: `Task failed ELB health checks` |
| then | No healthy target; the ALB fails open to a task that isn't listening: **502** |

Even without the forced deployment, users would have been hit about 25 minutes after the change,
with no deploy and no code change to blame.

### Fix

Restore the declared state with Terraform instead of re-adding the rule by hand, so the
fix is exactly what is in version control:

```bash
terraform -chdir=terraform plan  -var image_tag=<deployed-tag>   # expect: 1 to add
terraform -chdir=terraform apply -var image_tag=<deployed-tag>
```

ECS was still retrying, so the next task connected (`HikariPool-1 - Start completed`), became
healthy after its first checks, and `scripts/verify.sh` passed 9/9. A final
`terraform plan` reported `No changes`.

*Side finding:* the plan also showed `platform_version "1.4.0" -> "LATEST"`. Setting
`LATEST` explicitly caused a false diff on every plan, because AWS stores the resolved
version. The argument was removed so a clean plan really means "no drift".

### Prevention

- **Detect drift**: run `terraform plan` on a schedule (e.g. a nightly CI job) and alert on any
  diff. It found this change immediately.
- **Restrict who can change security groups**: an IAM or SCP deny on
  `ec2:RevokeSecurityGroupIngress` for humans, so changes only happen through Terraform.
- **Audit and alert**: CloudTrail records `RevokeSecurityGroupIngress`, with who made the call. An
  EventBridge rule on that event could notify immediately, instead of 25 minutes later.
- **Alert on the real signal**: the ALB 5xx alarm fires only once users are affected. An alarm on
  `UnHealthyHostCount > 0` or on ECS task stops would catch the crash loop earlier.
