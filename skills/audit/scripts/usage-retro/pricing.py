"""Per-model USD prices, from platform.claude.com/docs/en/about-claude/pricing, read 2026-09-13.
Prices are USD per million tokens: (base_input, create_5m, create_1h, cache_read, output).
Cache read is 0.1x base on every model except Fable/Mythos 5.1 (0.025x). Sonnet 5's $2/$10
introductory price became standard (page note). Keys are model-id prefixes, longest match wins.
"""
PRICES = {
    "claude-fable-5-1":  (10, 12.5, 20, 0.25, 50),
    "claude-fable-5":    (10, 12.5, 20, 1.00, 50),
    "claude-opus-5-5":   (4, 5, 8, 0.20, 20),  # claude.dev "What a task costs on Opus 5.5", 2026-09-25
    "claude-opus-5":     (5, 6.25, 10, 0.50, 25),
    "claude-opus-4-8":   (5, 6.25, 10, 0.50, 25),
    "claude-opus-4-7":   (5, 6.25, 10, 0.50, 25),
    "claude-sonnet-5":   (2, 2.50, 4, 0.20, 10),
    "claude-sonnet-4-6": (3, 3.75, 6, 0.30, 15),
    "claude-sonnet-4-5": (3, 3.75, 6, 0.30, 15),
    "claude-haiku-4-5":  (1, 1.25, 2, 0.10, 5),
}

def prices_for(model):
    best = None
    for k in PRICES:
        if (model or "").startswith(k) and (best is None or len(k) > len(best)):
            best = k
    return PRICES[best] if best else None

def usd(model, tok):
    """tok = (input, create_5m, create_1h, cache_read, output). None when the model is unpriced."""
    p = prices_for(model)
    if p is None:
        return None
    return sum(t * r for t, r in zip(tok, p)) / 1e6
