#!/usr/bin/env python3
"""Atas Artisan menu -> Supabase `menu-ingest`. Stdlib only; runs daily from a systemd timer on the VPS.

atasartisan.com is an iSeller store whose pages load the menu through form-encoded jQuery POSTs:
  /services/Liquid/Collections  -> the 5 collections
  /services/Liquid/Products     -> products of one collection (only the default variant)
  /services/Liquid/Product      -> one product with every variant and its options (Berat, Slice, ...)
About 40 requests a run, direct (no proxy). Photos stay on Atas's CDN; we keep only the URL, for the product
and, when iSeller has one, for each variant (variants[].image: a flavour's own photo).
Skips the upload when the menu is unchanged since the last run (hash in STATE); it then only reports the check.

env: ATASTE_INGEST_URL, ATASTE_SCRAPER_SECRET; STATE (default /var/lib/ataste-menu/last.sha256)
"""
import hashlib, html, http.cookiejar, json, os, re, sys, time, urllib.parse, urllib.request

SITE = "https://www.atasartisan.com"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36"
STATE = os.environ.get("STATE", "/var/lib/ataste-menu/last.sha256")

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
opener.addheaders = [("User-Agent", UA)]


def post(path, fields):
    """jQuery-style form POST: lists become key[]=v, dicts become key[sub]=v."""
    pairs = []
    for k, v in fields.items():
        if isinstance(v, list):
            pairs += [(f"{k}[]", x) for x in v]
        elif isinstance(v, dict):
            pairs += [(f"{k}[{s}]", x) for s, x in v.items()]
        else:
            pairs.append((k, v))
    req = urllib.request.Request(SITE + path, data=urllib.parse.urlencode(pairs).encode(),
                                 headers={"X-Requested-With": "XMLHttpRequest"})
    for attempt in range(3):
        try:
            with opener.open(req, timeout=30) as r:
                d = json.load(r)
            if not d.get("IsSuccess"):
                raise RuntimeError(f"{path}: {d.get('Message')}")
            return d["Data"]
        except Exception:
            if attempt == 2:
                raise
            time.sleep(3 * (attempt + 1))


def text(s):
    return html.unescape(re.sub(r"<[^>]+>", " ", s or "")).strip()


def src(x):
    """An iSeller image field: an object with src / preview_image, a bare URL, or null."""
    if isinstance(x, dict):
        return x.get("src") or x.get("preview_image") or ""
    return x if isinstance(x, str) else ""


def variant_image(v, value_images):
    """The variant's own photo, else the photo of one of its option values (a flavour), else ""."""
    own = src(v.get("image")) or src(v.get("featured_media"))
    if own:
        return own
    for o in v.get("options") or []:
        found = src(o.get("image")) or value_images.get((o.get("option_id"), o.get("value")), "")
        if found:
            return found
    return ""


def menu():
    opener.open(SITE + "/", timeout=30).read()  # session cookie
    cols = post("/services/Liquid/Collections", {"where": {"is_active": "true"}, "page": 0, "pageSize": 50,
                                                 "lang": "en", "includes": ["all_product_count"]})
    collections, products, seen = [], [], set()
    for ci, c in enumerate(cols):
        collections.append({"id": c["id"], "name": c["title"], "sort": ci})
        items = post("/services/Liquid/Products", {"collection": c["id"], "includes": ["discount", "selected_variant"],
                                                   "lang": "en", "pageSize": 200})
        for pi, p in enumerate(items):
            if p["id"] in seen:
                continue
            seen.add(p["id"])
            groups, variants = [], []
            if not p.get("has_only_default_variant", True):
                full = post("/services/Liquid/Product", {
                    "id": p["id"], "handle": p["handle"], "lang": "en",
                    "includes": ["discount", "selected_variant", "options_with_values", "variants.options"]})
                names = {o["id"]: o["name"] for o in full.get("options_with_values") or []}
                value_images = {(x.get("option_id"), x.get("value")): src(x.get("image"))
                                for o in full.get("options_with_values") or [] for x in o.get("values") or [] if src(x.get("image"))}
                groups = [{"name": o["name"], "choices": [v["value"] for v in sorted(o["values"], key=lambda v: v["position"])]}
                          for o in sorted(full.get("options_with_values") or [], key=lambda o: o["position"])]
                for v in full.get("variants") or []:
                    variant = {
                        "options": {names[o["option_id"]]: o["value"] for o in v.get("options") or [] if o["option_id"] in names},
                        "price": int(v.get("final_price") or v["price"]),
                        "available": bool(v.get("available")) and v.get("stock_status") != "out-of-stock",
                    }
                    image = variant_image(v, value_images)
                    if image:  # only when iSeller has one, so menus without variant photos hash the same as before
                        variant["image"] = image
                    variants.append(variant)
                time.sleep(0.5)  # be gentle with a small shop's server
            base = int(p.get("final_price") or p.get("price_min") or p["price"])
            products.append({
                "id": p["id"],
                "collection_id": c["id"],
                "name": p["title"].strip(),
                "description": text(p.get("description")),
                "photo_url": ((p.get("featured_image") or {}).get("src") or ""),
                "base_price": base,
                "option_groups": groups,
                "variants": variants,
                "available": bool(p.get("available")) and p.get("stock_status") != "out-of-stock",
                "sort": ci * 1000 + pi,
            })
    return {"collections": collections, "products": products}


def ingest(body):
    req = urllib.request.Request(os.environ["ATASTE_INGEST_URL"], data=json.dumps(body).encode(), method="POST",
                                 headers={"content-type": "application/json",
                                          "x-scraper-secret": os.environ["ATASTE_SCRAPER_SECRET"]})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode()


def main():
    m = menu()
    if not m["products"]:
        sys.exit("empty menu: refusing to upload")
    digest = hashlib.sha256(json.dumps(m, sort_keys=True).encode()).hexdigest()
    if os.path.exists(STATE) and open(STATE).read().strip() == digest and "--force" not in sys.argv:
        ingest({"checked": True})  # the app's "menu last updated" counts checks, not just changes
        print(f"unchanged ({len(m['products'])} products)")
        return
    print(ingest(m))
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    open(STATE, "w").write(digest)


if __name__ == "__main__":
    main()
