#!/usr/bin/env python3
"""After an upload: give the build to every external TestFlight group (Public, Invited), submit it for beta review,
and once testers can install it, raise app_release.min_build so older TestFlight builds must update.
Only the internal "Team" group gets builds by itself. Uses the App Store Connect API key in the Keychain
(asc-token.swift). Run it in the background: processing and beta review can take a while.

    ops/release/testflight.py 14
"""
import json, os, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.appstoreconnect.apple.com/v1"
WAITING = {"WAIT", "READY_FOR_BETA_SUBMISSION", "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED",
           "PROCESSING_EXCEPTION", "MISSING_EXPORT_COMPLIANCE"}


def call(path, data=None):
    token = subprocess.run(["swift", f"{HERE}/asc-token.swift"], capture_output=True, text=True, check=True).stdout.strip()
    req = urllib.request.Request(API + path, method="POST" if data else "GET",
                                 data=json.dumps({"data": data}).encode() if data else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        body = r.read()
    return json.loads(body) if body else None


def step(build):
    """Adds the build to missing external groups, submits it when ready; returns its external state."""
    app = call("/apps?filter[bundleId]=com.bayujo.Ataste")["data"][0]["id"]
    b = call(f"/builds?filter[app]={app}&filter[version]={build}&include=buildBetaDetail,betaGroups")
    if not b["data"] or b["data"][0]["attributes"]["processingState"] != "VALID":
        return "WAIT"
    bid = b["data"][0]["id"]
    has = {g["id"] for g in b["data"][0]["relationships"]["betaGroups"]["data"]}
    for g in call(f"/apps/{app}/betaGroups")["data"]:
        if not g["attributes"]["isInternalGroup"] and g["id"] not in has:
            call(f"/betaGroups/{g['id']}/relationships/builds", [{"type": "builds", "id": bid}])
    state = next(i for i in b["included"] if i["type"] == "buildBetaDetails")["attributes"]["externalBuildState"]
    if state == "READY_FOR_BETA_SUBMISSION":
        call("/betaAppReviewSubmissions", {"type": "betaAppReviewSubmissions",
                                           "relationships": {"build": {"data": {"type": "builds", "id": bid}}}})
    return state


def main(build):
    for _ in range(144):  # 10-minute checks for 24 h
        state = step(build)
        print(time.strftime("%H:%M"), f"build {build}: {state}", flush=True)
        if state == "IN_BETA_TESTING":
            break
        if state not in WAITING:
            sys.exit(f"stopping: unexpected state {state}")
        time.sleep(600)
    else:
        sys.exit("gave up after 24 h")
    pw = subprocess.run(["security", "find-generic-password", "-s", "ataste.db-password", "-a", "ataste", "-w"],
                        capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(["/opt/homebrew/opt/libpq/bin/psql",
                    "host=aws-0-ap-northeast-1.pooler.supabase.com port=5432 user=postgres.scgyssmzfurqjkgfomtq dbname=postgres",
                    "-c", f"update public.app_release set min_build = greatest(min_build, {int(build)}) where channel = 'testflight'"],
                   env={**os.environ, "PGPASSWORD": pw}, check=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: testflight.py <build number>"))
