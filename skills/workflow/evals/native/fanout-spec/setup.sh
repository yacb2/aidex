#!/bin/bash
set -e

mkdir -p src
for d in backlog plans decisions research references requests; do
  mkdir -p ".context/$d"
done
for d in backlog/_archive plans/_archive requests/_archive decisions/_archive; do
  mkdir -p ".context/$d"
done
mkdir -p _tmp

cat > CLAUDE.md <<'MD'
# billing-svc

Small internal Python service: authentication, payments, notifications and reports.
Four modules under `src/`, no framework. Tests are not wired up yet.
MD

cat > src/auth.py <<'PY'
import hashlib

SESSIONS = {}


def hash_password(password):
    return hashlib.md5(password.encode()).hexdigest()


def login(username, password, users):
    if users.get(username) == hash_password(password):
        token = username + "-token"
        SESSIONS[token] = username
        return token
    return None


def current_user(token):
    return SESSIONS.get(token)
PY

cat > src/payments.py <<'PY'
def apply_discount(amount, percent):
    if percent > 100:
        percent = 100
    return amount - (amount * percent / 100)


def charge(db, user_id, amount):
    query = "INSERT INTO charges (user_id, amount) VALUES ('%s', %s)" % (user_id, amount)
    db.execute(query)
    return amount


def refund(db, charge_id):
    db.execute("DELETE FROM charges WHERE id = " + str(charge_id))
PY

cat > src/notifications.py <<'PY'
import subprocess


def render(template, context):
    for key, value in context.items():
        template = template.replace("{{" + key + "}}", str(value))
    return template


def send_email(to, subject, body):
    cmd = "mail -s '%s' %s <<< '%s'" % (subject, to, body)
    subprocess.run(cmd, shell=True)


def notify_all(recipients, subject, body):
    for r in recipients:
        send_email(r, subject, body)
PY

cat > src/reports.py <<'PY'
import os


def monthly_totals(charges, month):
    total = 0
    for c in charges:
        if c["month"] == month:
            total += c["amount"]
    return total / len(charges)


def export(path, rows):
    full = os.path.join("/var/reports", path)
    with open(full, "w") as fh:
        for row in rows:
            fh.write(",".join(str(v) for v in row) + "\n")
    return full
PY
