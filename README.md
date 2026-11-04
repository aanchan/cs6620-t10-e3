# Topic 10 Assignment 3: Find the Fault with CloudWatch

**Type:** Post-class, individual
**Time:** about 1–2 hours
**Points:** 20


## Goal

You're the on-call engineer for a small service on AWS Lambda. First you set up monitoring. Then the service gets traffic. Something will go wrong. Your job is to find out what, using only CloudWatch.

Everyone's service is different. How yours breaks depends on your NUID.

## How it fits together

![Assignment 3 architecture](architecture.png)

- **Blue** tells you something is wrong (metrics, dashboard).
- **Red** tells a human (alarm, email).
- **Green** tells you where and why (logs, Logs Insights).

The labels show which part you build each piece in, and whether Terraform or you build it.

## What you need

- AWS Academy Learner Lab. Use region **us-east-1**.
- `main.tf`, `lambda_function.py`, and `load.sh` (attached).

**Naming rule:** use your NUID wherever you see `<NUID>`. Example: `obs-lab-001234567`.

## Part 1: Set up with Terraform

Terraform creates the service and the email topic for you. You build the monitoring yourself in Parts 2 and 3.

**Step A: Get ready**

1. Open **CloudShell** (top bar of the console). Check the region is **N. Virginia (us-east-1)**.
2. Upload `main.tf`, `lambda_function.py`, and `load.sh` (**Actions → Upload file**, one at a time).
3. Put them in one folder:
   ```
   mkdir -p obs && mv main.tf lambda_function.py load.sh obs/ && cd obs
   ```
4. Install Terraform (skip if `terraform -version` already works):
   ```
   mkdir -p ~/bin
   curl -sLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
   unzip -o /tmp/tf.zip -d ~/bin && export PATH=$HOME/bin:$PATH
   terraform -version
   ```
   You may see "Your version of Terraform is out of date." Ignore it. Any version 1.5 or newer works.

**Step B: Deploy**

```
terraform init
terraform apply -var="nuid=<NUID>" -var="email=<EMAIL>"
```

Type `yes` when asked. This creates:
- the Lambda function `obs-lab-<NUID>`,
- its log group,
- one test request, so CloudWatch starts receiving metrics,
- the SNS topic `obs-topic-<NUID>`, with your email subscribed.

**Step C: Confirm your email**

1. Check your inbox for an email from AWS Notifications. Click **Confirm subscription**. Check spam if you don't see it.
2. In **SNS → Topics → obs-topic-<NUID>**, the subscription should say **Confirmed**, not **Pending confirmation**. No alarm emails arrive until it's confirmed.

Metrics take 2–3 minutes to appear in CloudWatch. Confirm your email while you wait.

## Part 2: Build a dashboard

Lambda sends some metrics to CloudWatch automatically. Terraform didn't set them up, and you don't need to. You'll graph two: **Errors** and **Duration** (how long each request took).

Check the region in the top-right is **N. Virginia (us-east-1)**.

**Widget 1: Errors**

1. In the CloudWatch left menu, click **Dashboards → Create dashboard**. Name: `obs-dash-<NUID>`.
2. Choose **Line**, then **Metrics**.
3. Click **Lambda → By Function Name**. You'll see your function listed several times, once per metric. Tick the row where **Metric name** is **Errors**.
   - Don't see **Lambda** or your function? Type the function name in the search box. Still nothing? Wait a minute and refresh.
4. Set **Statistic** to **Sum** and **Period** to **1 minute**. Where to find these:
   - After you tick a metric, a tab called **Graphed metrics (1)** appears next to **Browse**, above the metric list. Click it.
   - Each ticked metric is a row there, with **Statistic** and **Period** columns. Click a value to change it.
5. Click **Create widget**.

**Widget 2: Duration**

6. Click **+** (Add widget). Choose **Line**, then **Metrics**.
7. **Lambda → By Function Name.** Tick your function's **Duration** row.
8. In the **Graphed metrics (1)** tab, set **Statistic** to **p99** and **Period** to **1 minute**.
   - **p99** means 99% of requests in that minute were faster than this value. It shows the slowest requests, which an average hides. More: [CloudWatch statistics definitions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Statistics-definitions.html).
9. Click **Create widget**, then **Save** (top right).

## Part 3: Create the alarm

1. Open **CloudWatch → Alarms → Create alarm → Select metric**.
2. **Lambda → By Function Name.** Tick your function's **Errors** row. Click **Select metric**.

**Page 1: Specify metric and conditions**

3. Statistic: **Sum**. Period: **1 minute**.
4. Threshold type: **Static**. Condition: **Greater/Equal**. Value: **4**.
5. Click **Next**.

**Page 2: Configure actions**

6. Under **Notification**, alarm state trigger: **In alarm**.
7. Choose **Select an existing SNS topic**. Pick `obs-topic-<NUID>`.
8. Leave the other actions (Lambda, Auto Scaling, EC2, Systems Manager) empty.
9. Click **Next**.

**Page 3: Add name and description**

10. Alarm name: `obs-alarm-<NUID>`. Click **Next**.

**Page 4: Preview and create**

11. Check the settings. Click **Create alarm**.

Your alarm will show **OK** or **Insufficient data**. That's normal. No traffic yet.

**Optional: put the alarm on your dashboard**

The alarm's own page shows a graph with a red threshold line. Dashboard widgets don't. You can add the alarm's graph to your dashboard:

1. Open your alarm. Click **Actions → Add to dashboard**.
2. Pick `obs-dash-<NUID>`. Click **Add to dashboard**.

Not required. It's useful to know for real on-call dashboards.

## Part 4: Go live

Your monitoring is ready. Now the service gets traffic.

1. Go back to CloudShell. You should still be in the `obs` folder.
2. **Write down the time.** Then run:
   ```
   chmod +x load.sh
   ./load.sh obs-lab-<NUID> 20
   ```
3. Open your dashboard. Set auto-refresh to **10 seconds** (dropdown next to the refresh button).
4. **Things will look normal for the first couple of minutes. That's expected, not a mistake.** Use the time to record a **baseline**: errors per minute and p99 duration while the service is healthy. You'll need it for Q1.
5. Wait for the alarm email. **Write down when it arrives.**
   - Alarm pages don't update by themselves. Click the **refresh button** (circular arrow) to see the latest state.

Notes:
- Traffic runs for 20 minutes, then stops on its own. That's enough for Part 5.
- Keep the CloudShell tab open. Closing it, or leaving it idle too long, stops the traffic. If it stops, run the command again and write down the new start time. The service will start healthy again.

## Part 5: Investigate

Answer each question with your own numbers.

**Q1. Detect.**
- About how many minutes after traffic started did the problems begin? How can you tell from the dashboard?
- How long from the problems starting to getting the alarm email? Why isn't it instant?
- Compare to your baseline. What changed on the dashboard? What **can't** the dashboard and alarm tell you about the problem?

**Q2. Localize.** Open **CloudWatch → Logs Insights**. Pick your function's log group. Set the time range to start **after the problems began** (from Q1), so the healthy minutes don't water down your numbers. Each request logs these fields: `route`, `item_id`, `status`, `latency_ms`. Failed requests also log `error`.

Write queries to find:
- the error rate for each route,
- the P95 latency for each route.

Which route is failing? Which route is slow? Give the numbers.

**Q3. Explain.** Find the pattern behind the failures. Which requests fail, and which don't? Show the query that proves it.

**Q4. Reflect.** Is CloudWatch a monitoring tool, an observability tool, or both? Use what you did in Q1–Q3 as evidence. One paragraph.

## What to submit

One PDF, in this order:

1. Screenshot: alarm history showing **In alarm**. Alarm name must be visible.
2. Screenshot: the alarm email you received.
3. Screenshot: your dashboard during traffic. Dashboard name must be visible.
4. Your Logs Insights queries for Q2 and Q3, with their results.
5. Answers to Q1–Q4.

## Rubric

| Item | Points |
|---|---|
| Alarm history (In alarm, NUID in name) | 3 |
| Alarm email | 2 |
| Logs Insights queries and results | 4 |
| Dashboard + Q1/Q2 numbers match your NUID | 3 |
| Q2: failing and slow routes correct | 3 |
| Q3: pattern correct, with proof | 3 |
| Q4: reflection uses your own work | 2 |

## Clean up

1. In the console, delete your alarm and dashboard. You made these by hand, so Terraform doesn't know about them.
2. In CloudShell, in the `obs` folder:
   ```
   terraform destroy -var="nuid=<NUID>" -var="email=<EMAIL>"
   ```
3. Stop your lab session.

CloudShell forgets `PATH` between sessions. If `terraform` isn't found later, run `export PATH=$HOME/bin:$PATH`.

## Bonus (not graded)

After you've built the alarm and dashboard by hand, add them to `main.tf` as `aws_cloudwatch_metric_alarm` and `aws_cloudwatch_dashboard` resources. Then you could rebuild the whole setup with one command.

## Notes

- Using AI to help write queries is fine. Your answers must come from your own data.
- We can see your lab activity. Results that don't match your NUID will be followed up.
