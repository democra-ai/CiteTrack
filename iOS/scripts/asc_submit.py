"""CiteTrack — App Store Connect submission helper.

Reuses JWT ES256 auth. Commands:
  state                     — show app, versions (state/releaseType), recent builds
  set-release <verId> <t>   — set releaseType (AFTER_APPROVAL | MANUAL)
  attach <verId> <buildId>  — attach a build to a version
  submit <verId>            — create+submit a reviewSubmission for the version
  full <buildNum> <ver>     — end-to-end: wait build ready -> version -> AFTER_APPROVAL -> attach -> submit

App: CiteTrack (id 6752281652), bundle com.citetrack.CiteTrack.
"""
import sys, time, json
import httpx, jwt

ISSUER_ID = "3186ba00-e12d-49f5-ab6c-2afa1abb9704"
KEY_ID = "2CX97KY6MD"
# key auto-discovered from either standard location
import os
KEY_PATH = next(p for p in [
    os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_2CX97KY6MD.p8"),
    os.path.expanduser("~/.achilles/appstore_api_key.p8"),
] if os.path.exists(p))
BASE = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6752281652"


def tok():
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode({"iss": ISSUER_ID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def req(method, path, payload=None, params=None):
    r = httpx.request(method, f"{BASE}{path}",
                      headers={"Authorization": f"Bearer {tok()}", "Content-Type": "application/json"},
                      json=payload, params=params, timeout=60)
    if r.status_code >= 400:
        print(f"ERROR {r.status_code} {method} {path}\n{r.text}", file=sys.stderr)
        if method == "GET" or r.status_code != 409:
            sys.exit(1)
    return r.json() if r.text else {}


def state():
    app = req("GET", f"/apps/{APP_ID}")["data"]
    print("APP:", app["attributes"]["name"], app["attributes"]["bundleId"])
    vers = req("GET", f"/apps/{APP_ID}/appStoreVersions", params={"limit": 10})["data"]
    print("\nVERSIONS:")
    for v in vers:
        a = v["attributes"]
        print(f"  id={v['id']}  {a['versionString']}  state={a['appStoreState']}  release={a.get('releaseType')}  platform={a['platform']}")
    builds = req("GET", f"/builds", params={"filter[app]": APP_ID, "limit": 8, "sort": "-version"})["data"]
    print("\nBUILDS (recent):")
    for b in builds:
        a = b["attributes"]
        print(f"  id={b['id']}  build={a['version']}  processing={a['processingState']}  expired={a.get('expired')}  uploaded={a.get('uploadedDate')}")


def find_build(buildnum):
    builds = req("GET", "/builds", params={"filter[app]": APP_ID, "filter[version]": str(buildnum), "limit": 5})["data"]
    return builds[0] if builds else None


def wait_build(buildnum, timeout=1800):
    print(f"Waiting for build {buildnum} to finish processing...")
    start = time.time()
    while time.time() - start < timeout:
        b = find_build(buildnum)
        if b:
            st = b["attributes"]["processingState"]
            print(f"  build {buildnum}: {st}")
            if st == "VALID":
                return b
            if st in ("INVALID", "FAILED"):
                print("Build processing failed.", file=sys.stderr); sys.exit(1)
        else:
            print(f"  build {buildnum}: not visible yet")
        time.sleep(30)
    print("Timed out waiting for build.", file=sys.stderr); sys.exit(1)


def get_or_create_version(ver):
    vers = req("GET", f"/apps/{APP_ID}/appStoreVersions", params={"limit": 20})["data"]
    for v in vers:
        if v["attributes"]["versionString"] == ver and v["attributes"]["platform"] == "IOS":
            print(f"Found version {ver}: id={v['id']} state={v['attributes']['appStoreState']}")
            return v
    print(f"Creating version {ver}...")
    v = req("POST", "/appStoreVersions", {
        "data": {"type": "appStoreVersions",
                 "attributes": {"platform": "IOS", "versionString": ver, "releaseType": "AFTER_APPROVAL"},
                 "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    print(f"Created version id={v['id']}")
    return v


WHATS_NEW = {
    "en-US": ("• New: Send feedback right from the app — Settings › Feedback\n"
              "• Google and Apple sign-in unlock AI-powered citation insights\n"
              "• Reliability and performance improvements"),
    "zh-Hans": ("• 新增：在应用内直接反馈——「设置 › 反馈」\n"
                "• 使用 Google 或 Apple 登录即可解锁 AI 引用洞察\n"
                "• 稳定性与性能优化"),
}


def set_whatsnew(verid):
    """Set 'What's New' text on each existing localization (fallback: default en text)."""
    locs = req("GET", f"/appStoreVersions/{verid}/appStoreVersionLocalizations", params={"limit": 50})["data"]
    if not locs:
        print("  (no localizations found on version — screenshots/description inherit from prior version)")
    for loc in locs:
        locale = loc["attributes"]["locale"]
        text = WHATS_NEW.get(locale, WHATS_NEW["en-US"])
        req("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {
            "data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                     "attributes": {"whatsNew": text}}})
        print(f"  set whatsNew for {locale}")


def set_release(verid, rtype="AFTER_APPROVAL"):
    req("PATCH", f"/appStoreVersions/{verid}", {
        "data": {"type": "appStoreVersions", "id": verid, "attributes": {"releaseType": rtype}}})
    print(f"Set releaseType={rtype} on version {verid}")


def attach(verid, buildid):
    req("PATCH", f"/appStoreVersions/{verid}/relationships/build", {
        "data": {"type": "builds", "id": buildid}})
    print(f"Attached build {buildid} to version {verid}")


def submit(verid):
    rs = req("POST", "/reviewSubmissions", {
        "data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                 "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
    rsid = rs["id"]
    print(f"Created reviewSubmission id={rsid}")
    req("POST", "/reviewSubmissionItems", {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rsid}},
                                   "appStoreVersion": {"data": {"type": "appStoreVersions", "id": verid}}}}})
    print("Added version to reviewSubmission")
    req("PATCH", f"/reviewSubmissions/{rsid}", {
        "data": {"type": "reviewSubmissions", "id": rsid, "attributes": {"submitted": True}}})
    print(f"SUBMITTED reviewSubmission {rsid} — Apple review requested, auto-release after approval.")


def full(buildnum, ver):
    b = wait_build(buildnum)
    v = get_or_create_version(ver)
    set_release(v["id"], "AFTER_APPROVAL")
    attach(v["id"], b["id"])
    set_whatsnew(v["id"])
    submit(v["id"])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "state"
    if cmd == "state": state()
    elif cmd == "set-release": set_release(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "AFTER_APPROVAL")
    elif cmd == "attach": attach(sys.argv[2], sys.argv[3])
    elif cmd == "submit": submit(sys.argv[2])
    elif cmd == "full": full(sys.argv[2], sys.argv[3])
    else: print("unknown cmd"); sys.exit(1)
