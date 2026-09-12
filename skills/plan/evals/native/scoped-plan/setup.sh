#!/bin/bash
set -e
mkdir -p .context/plans .context/references src/reports
printf '# Project\n\nSmall Django + Vue app. Monthly reports live in src/reports/.\n' > CLAUDE.md
cat > src/reports/models.py <<'PY'
from django.db import models


class Report(models.Model):
    month = models.DateField()
    title = models.CharField(max_length=200)


class ReportLine(models.Model):
    report = models.ForeignKey(Report, related_name="lines", on_delete=models.CASCADE)
    section = models.CharField(max_length=80)
    label = models.CharField(max_length=200)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
PY
cat > src/reports/render.py <<'PY'
from collections import OrderedDict

from django.template.loader import render_to_string
from weasyprint import HTML

from .models import ReportLine


def report_sections(report):
    """Group a report's lines by section, in insertion order."""
    sections = OrderedDict()
    for line in ReportLine.objects.filter(report=report).order_by("section", "label"):
        sections.setdefault(line.section, []).append(line)
    return sections


def render_pdf(report):
    """Render a monthly report to PDF."""
    html = render_to_string(
        "reports/monthly.html",
        {"report": report, "sections": report_sections(report)},
    )
    return HTML(string=html).write_pdf()
PY
cat > src/reports/views.py <<'PY'
from django.http import HttpResponse

from .models import Report
from .render import render_pdf


def export_pdf(request, report_id):
    report = Report.objects.get(pk=report_id)
    return HttpResponse(render_pdf(report), content_type="application/pdf")
PY
cat > src/reports/urls.py <<'PY'
from django.urls import path

from . import views

urlpatterns = [
    path("reports/<int:report_id>/export.pdf", views.export_pdf, name="report-export-pdf"),
]
PY
