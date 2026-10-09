#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

mkdir -p src/templates
cat > src/templates/orders.html <<'HTML'
<!-- Orders screen (Django template) -->
<main class="orders">
  <section class="filters">
    <label>Status <select name="status"></select></label>
    <label>Customer <input name="customer"></label>
    <label>From <input type="date" name="from"></label>
    <label>To <input type="date" name="to"></label>
    <label>Channel <select name="channel"></select></label>
    <label>Warehouse <select name="warehouse"></select></label>
    <button>Apply</button>
  </section>
  <table class="orders-table">
    <thead><tr><th>#</th><th>Customer</th><th>Total</th><th>Status</th><th></th></tr></thead>
    <tbody>{% for o in orders %}<tr><td>{{ o.id }}</td><td>{{ o.customer }}</td><td>{{ o.total }}</td><td>{{ o.status }}</td>
      <td><details class="menu"><summary>...</summary><a>Refund</a><a>Resend invoice</a><a>Cancel</a></details></td></tr>{% endfor %}</tbody>
  </table>
</main>
HTML
