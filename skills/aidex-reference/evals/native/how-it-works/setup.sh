#!/bin/bash
set -e
mkdir -p .context/references src/auth src/config
printf '# Project\n\nSmall Django service. Requests are authenticated with an API key\nheader; the middleware lives in src/auth/ and its configuration in src/config/.\n' > CLAUDE.md
cat > src/config/loader.py <<'PY'
import json
import os
from pathlib import Path

DEFAULTS = {
    "api_keys": [],
    "api_key_header": "X-Api-Key",
    "exempt_prefixes": ["/health", "/static"],
}

CONFIG_FILE = Path(os.environ.get("APP_CONFIG_FILE", "config/app.json"))


def _from_file():
    """Read the JSON config file, or return {} when it is absent."""
    if not CONFIG_FILE.exists():
        return {}
    return json.loads(CONFIG_FILE.read_text())


def _from_env():
    """Environment overrides. APP_API_KEYS is a comma-separated list."""
    env = {}
    raw_keys = os.environ.get("APP_API_KEYS")
    if raw_keys:
        env["api_keys"] = [k.strip() for k in raw_keys.split(",") if k.strip()]
    header = os.environ.get("APP_API_KEY_HEADER")
    if header:
        env["api_key_header"] = header
    return env


def load_config():
    """Resolve configuration: env var beats file, file beats default."""
    config = dict(DEFAULTS)
    config.update(_from_file())
    config.update(_from_env())
    return config
PY
cat > src/config/settings.py <<'PY'
from .loader import load_config

_config = load_config()

API_KEYS = _config["api_keys"]
API_KEY_HEADER = _config["api_key_header"]
EXEMPT_PREFIXES = _config["exempt_prefixes"]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "src.auth.middleware.ApiKeyMiddleware",
]
PY
cat > src/auth/middleware.py <<'PY'
from django.http import JsonResponse

from src.config import settings


def _header_name(header):
    """Django exposes request headers as HTTP_X_API_KEY in META."""
    return "HTTP_" + header.upper().replace("-", "_")


class ApiKeyMiddleware:
    """Reject any request that does not carry a known API key.

    Paths starting with one of settings.EXEMPT_PREFIXES are let through
    untouched, so the health check and static assets stay public.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def is_exempt(self, path):
        return any(path.startswith(prefix) for prefix in settings.EXEMPT_PREFIXES)

    def __call__(self, request):
        if self.is_exempt(request.path):
            return self.get_response(request)

        key = request.META.get(_header_name(settings.API_KEY_HEADER))
        if not key:
            return JsonResponse({"detail": "API key missing"}, status=401)
        if key not in settings.API_KEYS:
            return JsonResponse({"detail": "API key invalid"}, status=403)

        request.api_key = key
        return self.get_response(request)
PY
cat > src/auth/views.py <<'PY'
from django.http import JsonResponse


def whoami(request):
    """Echo back the key the middleware attached to the request."""
    return JsonResponse({"api_key": getattr(request, "api_key", None)})


def health(request):
    """Exempt from authentication via the /health prefix."""
    return JsonResponse({"status": "ok"})
PY
cat > src/auth/urls.py <<'PY'
from django.urls import path

from . import views

urlpatterns = [
    path("health", views.health, name="health"),
    path("whoami", views.whoami, name="whoami"),
]
PY
