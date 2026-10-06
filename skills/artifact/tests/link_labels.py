"""stdin -> stdout through wrap_report.link_field_labels: fixture helper for the
raw-page tests, whose pages skip the wrap and so never got the label links
check-artifact now requires of a consult notes box (BL-706)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "scripts", "dash"))
from wrap_report import link_field_labels  # noqa: E402

sys.stdout.write(link_field_labels(sys.stdin.read()))
