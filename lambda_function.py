"""
Observability Lab - seeded fault service (AWS Lambda, Python 3.12).

The SEED environment variable is your NUID (Terraform sets it).
Do not change this file.

Event format: {"route": "order", "item_id": 42, "elapsed": 130}
"elapsed" = seconds since load.sh started. The service is healthy at first,
then problems begin 1.5-3 minutes in.
"""
import json
import os
import random
import time

ROUTES = ["user", "order", "inventory", "payment", "search"]
BACKGROUND_ERROR_RATE = 0.002  # small random noise on every route


def build_config(seed):
    """Turn a seed into this deployment's faults."""
    seed = str(seed).strip().lstrip("0") or "0"  # "001234567" == "1234567"
    rng = random.Random(f"obs-lab-{seed}")
    failing_route, slow_route = rng.sample(ROUTES, 2)
    if rng.random() < 0.5:
        cause = {"type": "threshold", "value": rng.randrange(500, 701, 10)}
    else:
        cause = {"type": "modulo", "value": rng.choice([2, 3])}
    slow_ms = rng.randrange(1500, 3501, 100)
    onset_s = rng.randrange(90, 181, 30)  # problems start 1.5-3 minutes in
    return {
        "failing_route": failing_route,
        "slow_route": slow_route,
        "cause": cause,
        "slow_ms": slow_ms,
        "onset_s": onset_s,
    }


def cause_triggers(cause, item_id):
    if cause["type"] == "threshold":
        return item_id > cause["value"]
    return item_id % cause["value"] == 0


SEED = os.environ.get("SEED")
CONFIG = build_config(SEED) if SEED else None


def lambda_handler(event, context):
    if CONFIG is None:
        raise RuntimeError("SEED environment variable is not set")

    route = str(event.get("route", "user"))
    try:
        item_id = int(event.get("item_id", 1))
    except (TypeError, ValueError):
        item_id = 1

    if route not in ROUTES:
        print(json.dumps({"route": route, "item_id": item_id, "status": 400}))
        return {"statusCode": 400, "body": "unknown route"}

    try:
        elapsed = float(event.get("elapsed", 0))
    except (TypeError, ValueError):
        elapsed = 0
    broken = elapsed >= CONFIG["onset_s"]

    start = time.time()
    if broken and route == CONFIG["slow_route"]:
        time.sleep((CONFIG["slow_ms"] + random.uniform(-200, 200)) / 1000)
    else:
        time.sleep(random.uniform(0.02, 0.08))

    fault = (
        broken
        and route == CONFIG["failing_route"]
        and cause_triggers(CONFIG["cause"], item_id)
    )
    # No noise on test events (no "elapsed"), so the Terraform smoke test always passes.
    noise = not fault and "elapsed" in event and random.random() < BACKGROUND_ERROR_RATE
    failed = fault or noise

    record = {
        "route": route,
        "item_id": item_id,
        "status": 500 if failed else 200,
        "latency_ms": int((time.time() - start) * 1000),
    }
    if fault:
        record["error"] = f"{route} backend lookup failed for item {item_id}"
    elif noise:
        record["error"] = "upstream timeout"
    print(json.dumps(record))

    if failed:
        raise RuntimeError(record["error"])
    return {"statusCode": 200, "body": json.dumps({"route": route, "item_id": item_id})}
