# Invented sample sessions for the website screenshots. No real meetings.
# Usage: python3 -I site_samples.py <folder> <en|sk>. The folder is deleted and made again.
import json, os, sys, uuid, datetime as dt, shutil
root = sys.argv[1]
lang = sys.argv[2] if len(sys.argv) > 2 else "en"
shutil.rmtree(root, ignore_errors=True); os.makedirs(root)
now = dt.datetime.now().astimezone()
today = now.replace(hour=0, minute=0, second=0, microsecond=0)
T = {
 "en": {"weekly": "weekly sync", "sprint": "sprint planning", "client": "client onboarding", "retro": "team retro"},
 "sk": {"weekly": "týždenný sync", "sprint": "plánovanie sprintu", "client": "onboarding klienta", "retro": "retro tímu"},
}[lang]
def slug(t): return t.replace(" ", "_")
# (day offset, hour, minute, minutes, topic key or None, transcript?, outputs count, imported?, media MB)
S = [
 (0, 9, 0, 45, "weekly", True, 1, False, 38),
 (-1, 15, 30, 25, None, True, 0, False, 22),
 (-1, 10, 0, 52, "sprint", True, 2, False, 51),
 (-1, 9, 0, 18, None, False, 0, False, 15),
 (-2, 14, 0, 38, "client", True, 1, True, 31),
 (-3, 11, 0, 41, "retro", True, 1, False, 35),
]
for off, h, m, mins, key, tr, nout, imp, mb in S:
    start = today + dt.timedelta(days=off, hours=h, minutes=m)
    end = start + dt.timedelta(minutes=mins)
    name = start.strftime("%Y-%m-%d_%H-%M-%S")
    d = os.path.join(root, name)
    for sub in ("audio", "frames", "outputs"): os.makedirs(os.path.join(d, sub))
    with open(os.path.join(d, "audio", "system.m4a"), "wb") as f: f.write(os.urandom(int(mb * 0.25e6)))
    with open(os.path.join(d, "audio", "mic.m4a"), "wb") as f: f.write(os.urandom(int(mb * 0.15e6)))
    with open(os.path.join(d, "recording.mov"), "wb") as f: f.write(os.urandom(int(mb * 0.6e6)))
    outs = []
    if tr:
        with open(os.path.join(d, f"{name}_transcript.md"), "w") as f:
            f.write("# Transcript\n\n**[00:00:04] others:** Good morning.\n\n**[00:00:09] me:** Let's start.\n")
    day = start.strftime("%Y-%m-%d")
    for i in range(nout):
        fn = f"{day}_meetingsummary_{slug(T[key])}" + ("" if i == 0 else f"_v{i+1}") + ".md"
        p = os.path.join(d, "outputs", fn)
        with open(p, "w") as f: f.write(f"# {T[key]}\n\n## Decisions\n\n- Example decision.\n")
        t = (end + dt.timedelta(minutes=4 + 30 * i)).timestamp(); os.utime(p, (t, t))
        outs.append(fn)
    meta = {
        "id": str(uuid.uuid4()).upper(),
        "startedAt": start.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "endedAt": end.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "timeZone": "Europe/Bratislava",
        "displayName": None if imp else "Built-in Retina Display",
        "microphoneName": None if imp else "MacBook Pro Microphone",
        "video": "recording.mov",
        "audioTracks": [{"file": "audio/system.m4a", "speaker": "ostatní", "offset": 0}, {"file": "audio/mic.m4a", "speaker": "ja", "offset": 0}],
        "sourceEvents": [],
        "transcription": "done" if tr else "pending",
        "outputs": outs,
        "appVersion": "1.3.0",
        "source": "imported" if imp else "recorded",
    }
    if imp: meta["importedFileName"] = "client-call.m4a"
    meta = {k: v for k, v in meta.items() if v is not None}
    json.dump(meta, open(os.path.join(d, "session.json"), "w"), indent=2)
print("ok", len(S))
