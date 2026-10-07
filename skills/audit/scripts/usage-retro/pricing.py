"""Per-model USD prices, from platform.claude.com/docs/en/about-claude/pricing, read 2026-09-13; Haiku 5.5 and the Sonnet 5.5 cache-read cut added 2026-10-07
(aidex_ws/.context/research/2026-10-07-haiku-5-5-and-sonnet-cache-pricing.md).
Prices are USD per million tokens: (base_input, create_5m, create_1h, cache_read, output).
Cache read is 0.1x base, except Fable/Mythos 5.1 (0.025x) and Opus 5.5 / Sonnet 5.5 (0.05x). Sonnet 5's $2/$10
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
    "claude-sonnet-5-5": (2, 2.50, 4, 0.10, 10),  # cache read 0.20 -> 0.10 on 2026-10-07; own row so the sonnet-5 prefix cannot win
    "claude-sonnet-4-6": (3, 3.75, 6, 0.30, 15),
    "claude-sonnet-4-5": (3, 3.75, 6, 0.30, 15),
    "claude-haiku-4-5":  (1, 1.25, 2, 0.10, 5),
    # Haiku 5.5 is tiered by the REQUEST's prompt size: this is the <=100k tier. usd() prices aggregates, whose
    # per-request prompt size is unknown, so it stays on this tier; usd_request() applies HAIKU_5_5_HIGH.
    "claude-haiku-5-5":  (0.10, 0.125, 0.20, 0.01, 0.50),
}
HAIKU_5_5_HIGH = (0.50, 0.625, 1, 0.05, 2.50)  # one request with prompt > 100k tokens

def prices_for(model, tok=None):
    """Price tuple; tok = ONE request's tuple selects the Haiku 5.5 tier (exactly 100k is low)."""
    best = None
    for k in PRICES:
        if (model or "").startswith(k) and (best is None or len(k) > len(best)):
            best = k
    if best == "claude-haiku-5-5" and tok is not None and sum(tok[:4]) > 100_000:
        return HAIKU_5_5_HIGH
    return PRICES[best] if best else None

def usd(model, tok):
    """tok = (input, create_5m, create_1h, cache_read, output). None when the model is unpriced."""
    p = prices_for(model)
    if p is None:
        return None
    return sum(t * r for t, r in zip(tok, p)) / 1e6

def usd_request(model, tok):
    """Like usd() but tok is ONE API request, so the Haiku 5.5 >100k tier applies."""
    p = prices_for(model, tok)
    if p is None:
        return None
    return sum(t * r for t, r in zip(tok, p)) / 1e6
