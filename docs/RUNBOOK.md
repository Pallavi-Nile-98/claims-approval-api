# Runbook: break-fix exercises

Five failures deliberately induced on the live AWS deployment, one at a time, then
diagnosed with real tools and fixed. Each entry follows the same shape:
**symptom -> diagnosis commands -> root cause -> fix -> prevention**.

Timestamps are from the actual session (local time, EDT). Outputs are trimmed but real.

## At a glance

| # | Failure | What users saw | Decisive evidence | Fixed by |
|---|---|---|---|---|
| 1 | DB security group rule removed | Nothing for ~25 min, then **502** on every request | `Connect timed out` in app logs; DB security group `IpPermissions: []` | `terraform apply` (drift) |
| 2 | Execution role can't read the DB secret | Nothing (rollback) | `ResourceInitializationError ... AccessDeniedException ... ssm:GetParameters`, no app logs | `terraform apply` (drift) |
| 3 | Wrong ALB health check path | Mostly nothing (ALB fails open), intermittent 502 while tasks were replaced | `Target.ResponseCodeMismatch [404]`; ECS replacing tasks every few minutes | `terraform apply` (drift) |
| 4 | Bad `DB_URL` deployed | Nothing (rollback) | Exit code **1**; `FATAL: database "claim" does not exist` | Revert source, redeploy |
| 5 | Memory limit too low | Nothing (rollback) | Exit code **137**; `OutOfMemoryError: container killed due to memory usage`; log ends mid-startup | Revert source, redeploy |

**Patterns across all five:**

- **Read the exact error wording.** *Timed out* (network), *AccessDenied* (IAM), *ResponseCodeMismatch [404]* (wrong
  path), *database does not exist* (config) and exit *137* (memory) each point to a different layer.
- **Where it fails tells you the layer.** No app logs means it failed before the container ran (execution role,
  image, secrets). A stack trace means the problem is inside the app. A log that stops mid-sentence means the
  process was killed from outside.
- **"Steady state" does not mean "fixed".** The circuit breaker rolls back and reports stable. After a fix, confirm
  a **new** task on the **new** revision is running and healthy.
- **The 5xx alarm caught only one of five.** Rollbacks, fail-open and connection tracking hid the others from users
  and from the alarm. Production monitoring also needs `UnHealthyHostCount`, failed-deployment events
  and task-stop reasons.
- **Manual changes are drift.** `terraform plan` pinpointed failures 1-3 in one line each, and `apply` restored them
  exactly.

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

---

## 2. Task can't start: the execution role is missing permission to read the DB secret

**Note on the original brief**, which said "task role". On ECS, secrets injected into the container's
environment (`secrets` in the task definition) are fetched by the **execution role**, before the
app starts. The **task role** is what the application code uses while it runs. Removing the
permission from the task role would change nothing here, so the exercise uses the execution role.

**Induced by** replacing the execution role's inline policy with a copy that lacks only the
`ReadDbPassword` statement (`ssm:GetParameters` on the one parameter), then forcing a new
deployment, because secrets are only fetched when a task starts:

```bash
aws iam put-role-policy --role-name claims-approval-api-execution --policy-name least-privilege \
  --policy-document file://exec-policy-without-ssm.json
aws ecs update-service --cluster claims-approval-api --service claims-approval-api --force-new-deployment
```

### Symptom

- **Users: none.** `scripts/verify.sh` kept passing 9/9 throughout.
- **ECS:** every new task stopped within ~30 seconds with `ResourceInitializationError`, and
  the application wrote **no logs at all**. After 4 attempts the deployment failed and rolled back.

### Diagnosis

```bash
# 1. Service events: the whole answer is in the message.
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].events[:5].[createdAt,message]' --output text
#   was unable to place a task. Reason: ResourceInitializationError: unable to pull secrets or
#   registry auth: ... unable to retrieve secrets from ssm ... api error AccessDeniedException:
#   User: arn:aws:sts::<acct>:assumed-role/claims-approval-api-execution/<task-id>
#   is not authorized to perform: ssm:GetParameters on resource:
#   arn:aws:ssm:us-east-2:<acct>:parameter/claims-approval-api/db/password
#   because no identity-based policy allows the ssm:GetParameters action.

# 2. Confirm in IAM what the role actually allows.
aws iam get-role-policy --role-name claims-approval-api-execution --policy-name least-privilege \
  --query 'PolicyDocument.Statement[].Sid' --output text
#   EcrLogin  PullAppImage  WriteAppLogs        <- ReadDbPassword is gone

# 3. Drift detection.
terraform -chdir=terraform plan -var image_tag=<deployed-tag>
#   ~ aws_iam_role_policy.execution will be updated in-place
#   + Sid = "ReadDbPassword"  Action = "ssm:GetParameters"
```

**How to read an AccessDenied message:** it names **who** was denied (`assumed-role/claims-approval-api-execution`,
so the execution role, not the task role), **what** action (`ssm:GetParameters`), on **which** resource (the
parameter ARN), and **why** (`no identity-based policy allows` means nothing grants it; an explicit
deny would say so). That is enough to write the missing policy statement.

**Where the failure happens tells you the layer:**

| Evidence | Layer |
|---|---|
| `ResourceInitializationError`, no app logs | ECS agent, before the container starts: image pull, secrets, log setup (**execution role**) |
| App logs with a stack trace | Inside the application: config, DB, code (failures 1 and 4) |
| Exit code 137 | The container was killed: memory (failure 5) |

### Root cause

The execution role lost `ssm:GetParameters` on the DB password parameter, so the ECS agent could
not fetch the secret it must inject into the container, and every new task failed before the
application started.

Users were unaffected because of the rolling deployment (`minimum healthy percent = 100`): ECS only
stops the old task once a new one is healthy, so the old task, which already had its password in
memory, kept serving. After repeated failures the **deployment circuit breaker** marked the
deployment failed and rolled back.

### Fix

```bash
terraform -chdir=terraform plan  -var image_tag=<deployed-tag>   # expect: 0 to add, 1 to change
terraform -chdir=terraform apply -var image_tag=<deployed-tag>
```

**Trap:** right after the apply, the service reported `deployment completed` and `steady state`, and
`verify.sh` passed. But the events showed that this was the **rollback** completing
(`deployment failed: tasks failed to start` -> `rolling back to deployment ...`): the old task was
still running, and nothing had yet proved the fix. A forced new deployment did: a new task
started, fetched the secret, connected to RDS (`HikariPool-1 - Start completed`) and became healthy.

> "Steady state" means ECS is running what it wants to run, which may be the old version.
> After a fix, confirm that a **new** task started and is healthy.

### Prevention

- **Change IAM only through Terraform** and review the plan: the diff showed exactly which
  statement was missing. Deny `iam:PutRolePolicy` to humans outside the pipeline.
- **Keep the circuit breaker with rollback**: it kept users unaffected and stopped the retry loop.
- **Alarm on failed deployments**: an EventBridge rule on ECS
  `SERVICE_DEPLOYMENT_FAILED` events catches this immediately, whereas the 5xx alarm never
  fired because users never saw an error.
- **Check new IAM changes before deploying**: the IAM policy simulator
  (`aws iam simulate-principal-policy`) can confirm that the execution role allows `ssm:GetParameters` on the
  parameter ARN.

---

## 3. Targets unhealthy: wrong ALB health check path

**Induced by** changing the target group's health check path to a page that doesn't exist,
the kind of typo a console edit could introduce:

```bash
aws elbv2 modify-target-group --target-group-arn <tg-arn> --health-check-path /actuator/healthz
```

### Symptom

- **Users mostly unaffected.** `scripts/verify.sh` passed 9/9 while the only target was marked `unhealthy`.
- **ECS churn:** `Amazon ECS replaced 1 tasks due to an unhealthy status`, every few minutes. Left
  running unnoticed for about **33 hours** (Oct 2 16:48 to Oct 4 01:28), this produced a continuous loop
  of task replacements. ECS only lists stopped tasks for about an hour, and 17 were listed.
- During each replacement, the ~80 s while the new JVM starts can return **502** to users:
  an intermittent outage that's easy to miss.

### Diagnosis

```bash
# 1. What does the load balancer think, and why? The Reason and Description fields matter.
aws elbv2 describe-target-health --target-group-arn <tg-arn> \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output text
#   10.0.1.129  unhealthy  Target.ResponseCodeMismatch  Health checks failed with these codes: [404]

# 2. What is ECS doing about it?
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].events[:4].[createdAt,message]' --output text
#   has stopped 1 running tasks ... deregistered 1 targets ... has started 1 tasks ...
#   Amazon ECS replaced 1 tasks due to an unhealthy status

# 3. What exactly is being checked?
aws elbv2 describe-target-groups --target-group-arns <tg-arn> \
  --query 'TargetGroups[0].[HealthCheckPath,Matcher.HttpCode]' --output text
#   /actuator/healthz   200

# 4. Reproduce the check from outside, through the ALB.
curl -s -o /dev/null -w '%{http_code}\n' http://<alb-dns>/actuator/healthz    # 404
curl -s -o /dev/null -w '%{http_code}\n' http://<alb-dns>/actuator/health     # 200
```

**Target health reason codes are the fastest clue:**

| Reason | Meaning |
|---|---|
| `Target.ResponseCodeMismatch` + `[404]` | The app answers, but not on that path: wrong **path** |
| `Target.ResponseCodeMismatch` + `[503]` | The app answers but says it is unhealthy, e.g. DB down (failure 1) |
| `Target.Timeout` | No answer in time: security group, app hung, or still starting |
| `Target.FailedHealthChecks` | Connection failed: not listening yet, crashed |
| `Elb.InitialHealthChecking` | Still in the first checks after registration |

### Root cause

The target group's health check path was changed to `/actuator/healthz`, which the app does not
serve, so every health check got a 404 where 200 was expected and the healthy app was marked unhealthy.

Two AWS behaviours shaped what users saw:

- **The ALB fails open.** When *every* target in a target group is unhealthy, the ALB routes to all of
  them anyway, on the basis that a possibly-broken backend beats a guaranteed 503. That's why traffic kept
  working.
- **ECS acts on the ALB's verdict.** A service attached to a target group replaces any task the ALB
  reports unhealthy (after the grace period), so the healthy app was killed and restarted repeatedly.

### Fix

```bash
terraform -chdir=terraform plan  -var image_tag=<deployed-tag>
#   ~ health_check { ~ path = "/actuator/healthz" -> "/actuator/health" }
#   Plan: 0 to add, 1 to change, 0 to destroy
terraform -chdir=terraform apply -var image_tag=<deployed-tag>
```

Verified by the target turning `healthy`, the **same task** still running four minutes later (no more
replacements), `verify.sh` 9/9, and `terraform plan` reporting `No changes`.

### Prevention

- **Alarm on `UnHealthyHostCount > 0`** for the target group. This failure ran for about 33 hours, and the
  5xx alarm never fired because fail-open kept most requests succeeding.
- **Alarm on task churn**: an EventBridge rule on ECS task state changes with `stoppedReason`
  containing "unhealthy", or a metric on the number of tasks started per hour.
- **Keep health check settings in Terraform only**; `terraform plan` showed the drift as a single
  clear line.
- **Health endpoints are a contract**: if the app ever changes its health path, change the ALB in the
  same pull request. A test (`HealthEndpointIT`) already pins `/actuator/health` to 200 in the app.
- **Operational habit:** destroy, or at least check, the stack before stepping away mid-exercise. This
  incident ran unattended for about 33 hours, roughly $2.50 of avoidable cost at about $0.07/hour.

---

## 4. App fails to start: wrong environment variable (bad `DB_URL` deployed)

**Induced by** a developer-style mistake rather than a console change: the database name in
`DB_URL` was mistyped (`claims` -> `claim`) in a **local, never-committed** edit of `terraform/ecs.tf`,
then deployed with `terraform apply`. The hardcoded literal replaced the `${var.db_name}` reference:

```diff
- db_url = "jdbc:postgresql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}?sslmode=require"
+ db_url = "jdbc:postgresql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/claim?sslmode=require"
```

The apply registered task definition **revision 5** and pointed the service at it.

### Symptom

- **Users: none.** `scripts/verify.sh` passed 9/9 throughout.
- **ECS:** each revision-5 task started, ran for about a minute, and exited. About seven minutes after the
  deploy, the service events showed:

```
03:10:10  (deployment ecs-svc/0595...) deployment failed: tasks failed to start.
03:10:10  rolling back to deployment ecs-svc/6383...
03:10:41  has stopped 1 running tasks
```

### Diagnosis

```bash
# 1. Service events: a failed deployment and an automatic rollback.
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].events[:6].[createdAt,message]' --output text

# 2. Which revision is actually running now? (PRIMARY after the rollback = revision 4)
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].deployments[].[status,rolloutState,taskDefinition,runningCount,failedTasks]' --output text
#   PRIMARY  COMPLETED  claims-approval-api:4  1  0

# 3. How did the stopped tasks die? Group them by revision and exit code.
for t in $(aws ecs list-tasks --cluster claims-approval-api --desired-status STOPPED --query 'taskArns' --output text); do
  aws ecs describe-tasks --cluster claims-approval-api --tasks $t \
    --query 'tasks[0].[taskDefinitionArn,containers[0].exitCode,stoppedReason]' --output text
done | sort | uniq -c
#   3 claims-approval-api:5  1  Essential container in task exited
#   1 claims-approval-api:5  1  Scaling activity initiated by (deployment ...)   <- stopped by the rollback

# 4. The application's own error (read the last "Caused by").
aws logs tail /ecs/claims-approval-api --since 10m --format short | grep -E 'FATAL|Caused by'
#   Caused by: org.postgresql.util.PSQLException: FATAL: database "claim" does not exist
```

**Exit code 1** means the application exited on its own with an error (compare with 137 in failure 5,
where the process is killed from outside).

**The wording of the database error narrows it down immediately.** Unlike failure 1's
`Connect timed out`, here **PostgreSQL itself answered**. So the network, security groups, TLS and
even the password all worked: PostgreSQL only checks whether the database exists *after* authenticating
the user. The only thing left is the configuration value.

### Root cause

A typo in the `DB_URL` environment variable (`/claim` instead of `/claims`) was deployed in task
definition revision 5. Every new task authenticated to RDS but asked for a database that doesn't exist,
so Flyway, and with it the whole Spring context, failed at startup.

Users never noticed because the rolling deployment kept the revision-4 task serving, and the
**deployment circuit breaker** marked the deployment failed and rolled back on its own.

### Fix

**The circuit breaker fixed the outage, not the cause.** Terraform's desired state still said `claim`,
so the next `terraform apply` by anyone would have shipped the typo again. The fix belongs in source:

```bash
git restore terraform/ecs.tf          # in a team: git revert <bad-commit> and merge
terraform -chdir=terraform plan  -var image_tag=<deployed-tag>
#   -/+ aws_ecs_task_definition.app   # forces replacement:  .../claim?... -> .../claims?...
#   ~   aws_ecs_service.app
#   Plan: 1 to add, 1 to change, 1 to destroy
terraform -chdir=terraform apply -var image_tag=<deployed-tag>
```

The "1 to destroy" is not data: task definitions are immutable, so a change registers a new revision
(6) and deregisters the old one (5).

Verified by checking that the running task is **revision 6** and started after the apply (a new task,
not the rollback), its `DB_URL` ends in `/claims?sslmode=require`, the target is healthy, `verify.sh`
passes 9/9, `terraform plan` reports `No changes`, and `git status` is clean.

### Prevention

- **Reference values, don't retype them.** The bug was a literal that replaced `${var.db_name}`. Values
  derived from Terraform resources and variables can't drift apart.
- **Deploy through `scripts/deploy.sh`, not a bare `terraform apply`.** This bad deploy used a bare
  apply, which reported success. `deploy.sh` compares the running revision with the one it registered
  and fails loudly on a rollback (`ECS rolled back: running :4, expected :5`).
- **Review infrastructure changes with the plan output in the pull request.** The one-word diff in
  `DB_URL` was plainly visible in the plan.
- **Alert on `SERVICE_DEPLOYMENT_FAILED`** (EventBridge, ECS deployment state change events). The 5xx
  alarm stays silent when a rollback protects users.
- **Keep the circuit breaker with rollback enabled.** It turned a potential outage into a non-event.

---

## 5. Container killed: memory limit too low (OOM)

**Note on the original brief**, which said "task memory set too low". On Fargate the smallest task size for
0.25 vCPU is **512 MiB**, and this image sizes the Java heap as a percentage of the container's memory
(`-XX:MaxRAMPercentage=75`). Measured locally with Docker under the same conditions as Fargate (no swap:
`--memory=X --memory-swap=X`):

| Memory limit | Result |
|---|---|
| 1 GiB | healthy, ~330 MiB used |
| 512 MiB (Fargate minimum) | healthy, ~294 MiB used |
| 256 MiB | healthy, 238 of 256 MiB used (the heap shrank to fit) |
| **192 MiB** | **killed during startup, 2 of 2 runs: `OOMKilled=true`, exit code 137** |

So the smallest task size can't make this app run out of memory. The realistic way it happens on
Fargate is a **container-level hard limit** (`memory` in the container definition) set below what
the JVM needs. The kernel enforces it the same way (a cgroup memory limit), with the same symptoms.
Testing locally first predicted the outcome before anything was changed in AWS.

**Induced by** a local, never-committed edit adding `memory = 192` to the container definition (the task
stayed at 1024 MiB), deployed with `terraform apply` as task definition **revision 7**.

### Symptom

- **Users: none.** The revision-6 task kept serving; the circuit breaker rolled back at 05:32:37.
- **ECS:** four revision-7 tasks, each killed about 1.5-2 minutes into startup.

### Diagnosis

```bash
# 1. Service events: failed deployment and rollback (same shape as failure 4).
aws ecs describe-services --cluster claims-approval-api --services claims-approval-api \
  --query 'services[0].events[:5].[createdAt,message]' --output text
#   (deployment ...) deployment failed: tasks failed to start.
#   rolling back to deployment ...

# 2. How did the tasks die? The task-level stoppedReason is generic
#    ("Essential container in task exited"); the CONTAINER's reason is the answer.
for t in $(aws ecs list-tasks --cluster claims-approval-api --desired-status STOPPED --query 'taskArns' --output text); do
  aws ecs describe-tasks --cluster claims-approval-api --tasks $t \
    --query 'tasks[0].[taskDefinitionArn,containers[0].exitCode,containers[0].reason]' --output text
done
#   claims-approval-api:7  137  OutOfMemoryError: container killed due to memory usage   (x4)
#   claims-approval-api:4  143  None                                                      (normal stop)

# 3. How does the log end? Mid-startup, with no error and no stack trace.
aws logs tail /ecs/claims-approval-api --since 5m --format short | tail -5
#   ... HHH000412: Hibernate ORM core version 6...
#   ... HHH000026: Second-level cache disabled            <- then nothing

# 4. Compare the memory settings: task vs container.
aws ecs describe-task-definition --task-definition claims-approval-api:7 \
  --query 'taskDefinition.[memory,containerDefinitions[0].memory]' --output text
#   1024   192
```

**Exit codes:**

| Exit code | Meaning | Log ends with |
|---|---|---|
| `1` | The app exited by itself on an error (failure 4) | A `Caused by:` stack trace |
| `137` = 128 + 9, SIGKILL | Killed instantly from outside, here by the kernel OOM killer | Nothing: cut off mid-startup |
| `143` = 128 + 15, SIGTERM | Asked to stop, e.g. ECS replacing a task during a deploy | A graceful shutdown |

### Root cause

The container's hard memory limit (192 MiB) was below what this JVM needs to start. `MaxRAMPercentage`
only sizes the **heap** (here 75% of 192 = 144 MiB). The memory outside the heap (class metadata for
Spring and Hibernate, JIT code cache, thread stacks, GC structures) needs well over 100 MiB on its own,
so total usage crossed the limit during startup and the kernel killed the process.

### Fix

```bash
git restore terraform/ecs.tf
terraform -chdir=terraform plan  -var image_tag=<deployed-tag>   # - memory = 192 ; 1 to add, 1 to change, 1 to destroy
terraform -chdir=terraform apply -var image_tag=<deployed-tag>
```

Verified the same way as failure 4: revision 8 has task memory 1024 MiB and no container limit, the
PRIMARY deployment and the running task are revision 8 (started after the apply), the target is
healthy, `verify.sh` passes 9/9, `terraform plan` reports `No changes`, and `git status` is clean.

### Prevention

- **Size memory from measurements, with headroom.** This app peaks around 330 MiB; 1024 MiB leaves room for
  traffic spikes. Re-measure after adding dependencies.
- **Size the heap as a percentage of the container's memory** (`MaxRAMPercentage`), never a fixed `-Xmx`.
  It's why 512 and even 256 MiB still worked: a fixed heap tuned for a bigger box is the classic cause of
  OOM kills after someone "saves cost" by shrinking the task.
- **Avoid container-level hard limits** on single-container Fargate tasks. The service's `MemoryUtilization`
  metric is measured against **task** memory, so a container killed at 192 of its own 192 MiB would show
  only about 19% (192/1024) there, which is misleading.
- **Alert on task stops with an OOM reason**: an EventBridge rule on ECS task state changes where
  `containers[].reason` contains `OutOfMemoryError`.
- **Test the limit before deploying**: `docker run --memory=X --memory-swap=X` reproduced the exact
  behaviour locally in minutes.
