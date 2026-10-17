"""BeamNG's own rally system for the career's stages (A9): python tools/make_rally_stages.py

sl_rally's four stages (mod/street_legal/rally/west_coast_usa.json) have no notebooks, because the level has none. The game's codriver (gameplay_rally, the
RallyManager) plays a structured notebook against a driveline, so this writes, for every stage, a mission-shaped folder that gameplay_rally.loadMission
reads (no info.json, so the game's mission scanner leaves it alone):

  mod/street_legal/rally/stages/<id>/race.race.json                    start and finish pathnodes, the start positions
  mod/street_legal/rally/stages/<id>/rally/drivelineSpline.json        the stage's line (nodes, tangents, widths)
  mod/street_legal/rally/stages/<id>/rally/notebooks/structured.notebook.json   one pacenote per corner, a cornerStart and a cornerEnd waypoint each

A structured note with a plain corner in slot 4 is turned into the call ("left 3") by the game from the angle it measures between the two waypoints, and
spoken with a shared voicepack (compositors/voicepacks/ak_*), so no recording is needed. Corners are found from the line's heading change.
"""
import hashlib
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "mod", "street_legal", "rally", "west_coast_usa.json")
OUT = os.path.join(HERE, "..", "mod", "street_legal", "rally", "stages")

WINDOW = 3            # nodes either side (20 m at 5 m spacing) the heading change is measured over
TURN_PER_M = 0.18     # degrees per metre of heading change that counts as turning
MIN_ANGLE = 15.0      # degrees a corner must turn in all
GAP = 2               # nodes a corner may pause for and still be the same corner
MAX_NODES = 12        # nodes (about 70 m) one called corner may span
MIN_APART = 4         # nodes between the end of one note and the start of the next


def unit(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / n for c in v]


def tangents(pts):
    out = []
    for i in range(len(pts)):
        a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
        out.append(unit([b[0] - a[0], b[1] - a[1], b[2] - a[2]]))
    return out


def heading(t):
    return math.degrees(math.atan2(t[1], t[0]))


def wrap(d):
    return (d + 180.0) % 360.0 - 180.0


def corners(pts):
    """[(first node, last node, signed total degrees)] where the line turns."""
    tan = tangents(pts)
    hd = [heading(t) for t in tan]
    spacing = sum(math.dist(pts[i][:2], pts[i + 1][:2]) for i in range(len(pts) - 1)) / max(1, len(pts) - 1)
    rate = []
    for i in range(len(pts)):
        a, b = max(0, i - WINDOW), min(len(pts) - 1, i + WINDOW)
        rate.append(wrap(hd[b] - hd[a]) / max(1e-6, (b - a) * spacing))
    out, i = [], 0
    while i < len(pts):
        if abs(rate[i]) >= TURN_PER_M:
            j, last = i, i
            while j < len(pts) and (abs(rate[j]) >= TURN_PER_M or j - last <= GAP):
                if abs(rate[j]) >= TURN_PER_M:
                    last = j
                j += 1
            total = wrap(hd[min(len(pts) - 1, last + 1)] - hd[max(0, i - 1)])
            if abs(total) >= MIN_ANGLE and (not out or i - out[-1][1] >= MIN_APART):
                # a long sweep is called as several corners, each at most MAX_NODES long
                n = max(1, -(-(last - i + 1) // MAX_NODES))
                size = (last - i + 1) / n
                for k in range(n):
                    lo, hi = i + int(round(k * size)), i + int(round((k + 1) * size)) - 1
                    part = wrap(hd[min(len(pts) - 1, hi + 1)] - hd[max(0, lo - 1)])
                    if abs(part) >= MIN_ANGLE / 2:
                        out.append((lo, hi, part))
            i = last + 1
        else:
            i += 1
    return out


def quat_for(t):
    phi = math.atan2(-t[0], t[1])
    return [0.0, 0.0, math.sin(phi / 2), math.cos(phi / 2)]


def wp(name, wtype, pos, t, oid):
    return {"name": name, "normal": [round(c, 6) for c in t], "oldId": oid, "pos": [round(c, 3) for c in pos], "radius": 8, "waypointType": wtype}


def notebook(stage, pts, tan):
    notes, oid = [], 2
    # the game cuts the route at the start position and at the stop zone and drops a waypoint that falls before one or on top of another racing point:
    # no note may start within KEEP_CLEAR nodes of the start or end within that of the finish
    n = 0
    for a, b, _ in corners(pts):
        if a - 1 < KEEP_CLEAR or b > len(pts) - 1 - KEEP_CLEAR:
            continue
        n += 1
        a = max(0, a - 1)
        notes.append({
            "audioMode": 1, "distanceBeforeModifier": True, "ignoreDistanceCalls": False, "includeLinkWord": True, "isolate": False, "metadata": {},
            "name": "Pacenote %d" % n, "oldId": oid,
            "pacenoteWaypoints": [wp("corner start", "cornerStart", pts[a], tan[a], oid + 1), wp("corner end", "cornerEnd", pts[b], tan[b], oid + 2)],
            "pk": hashlib.sha1(("%s:%d" % (stage["id"], n)).encode()).hexdigest()[:8],
            "slowCorner": False, "slowCornerReleaseType": 30,
            "structured": {"items": {"1": {}, "2": {}, "3": {}, "4": {"type": "corner"}, "5": {}, "6": {}}, "schemaVersion": 3},
            "todo": False, "triggerType": 15})
        oid += 3
    return {"audioMode": 4, "authors": "Street Legal", "created_at": 1784000000, "description": "", "metadata": {}, "name": "structured",
            "pacenotes": notes, "updated_at": 1784000000, "version": "4"}


def pathnode(name, oid, pos, t):
    return {"customFields": {"names": {}, "tags": {}, "types": {}, "values": {}}, "mode": "manual", "name": name, "navRadiusScale": 1,
            "normal": [round(c, 6) for c in t], "oldId": oid, "pos": [round(c, 3) for c in pos], "radius": 10, "recovery": -1, "reverseRecovery": -1,
            "sidePadding": [1, 3], "useAsSplit": False, "visible": True}


def race(stage, pts, tan):
    stop = [pts[-1][j] + tan[-1][j] * STOP_BEYOND for j in range(3)]
    return {"authors": "Street Legal", "classification": {"allowRollingStart": False, "branching": False, "closed": False, "reversible": False},
            "date": 1784000000, "defaultLaps": 1, "defaultStartPosition": 2, "description": stage["name"], "difficulty": 20, "endNode": -1,
            "forwardPrefabs": {}, "hideMission": False, "name": stage["name"], "pacenotes": {},
            "pathnodes": [pathnode("Pathnode 1", 4, pts[0], tan[0]), pathnode("Pathnode 2", 5, pts[-1], tan[-1])],
            "prefabs": {}, "reversePrefabs": {}, "reverseStartPosition": -1, "rollingReverseStartPosition": -1, "rollingStartPosition": -1,
            "segments": [{"capsules": {}, "from": 4, "mode": "waypoint", "name": "Segment 1->2", "oldId": 6, "to": 5}],
            "simplifyAiPath": False, "startNode": 4,
            "startPositions": [{"group": "start", "name": "SS_start_line", "oldId": 2, "pos": [round(c, 3) for c in pts[0]], "rot": quat_for(tan[0])},
                               {"group": "start", "name": "SS_stop_control", "oldId": 3, "pos": [round(c, 3) for c in stop], "rot": quat_for(tan[-1])}]}


KEEP_CLEAR = 5        # nodes (25 m) a pacenote keeps from the start and the finish
STOP_BEYOND = 30.0    # metres past the finish line where the stop control stands (the game keeps the route only up to it, and the finish must come before)
PAD_NODES = 10        # nodes of straight road added before the start and after the finish (the game wants the driveline to reach beyond both)
PAD_STEP = 5.0


def padded(pts, tan):
    """The stage's line with a straight lead-in and run-out, so the first note's start and the finish line both lie on the driveline."""
    t0, t1 = tan[0], tan[-1]
    before = [[pts[0][j] - t0[j] * PAD_STEP * k for j in range(3)] for k in range(PAD_NODES, 0, -1)]
    after = [[pts[-1][j] + t1[j] * PAD_STEP * k for j in range(3)] for k in range(1, PAD_NODES + 1)]
    return before + [list(p) for p in pts] + after, [t0] * PAD_NODES + list(tan) + [t1] * PAD_NODES


def spline(stage, pts, tan):
    pts, tan = padded(pts, tan)
    return {"name": "Rally Driveline", "version": 1, "isLoop": False, "nodes": [[round(c, 3) for c in p] for p in pts],
            "nmls": [[round(c, 5) for c in t] for t in tan],
            "properties": {"liaisonAllocatedTimeMins": 5, "useRaycast": True, "speedLimitKph": 100, "vertRayRaise": 2},
            "widths": [stage.get("width", 8)] * len(pts),
            "stats": {"raceDistanceKms": round(stage.get("length", 0) / 1000, 3), "surfacePercentages": {"gravel": 100.0}}}


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1)


APART = 90.0          # metres the stop control and the finish keep from the start: the game places a point on the closest piece of the line, so a loop that ends
                      # beside its start would put the finish and the stop zone on the first metres


def trimmed(pts):
    """A line that comes back to its start is cut short so that its end, with the 30 m to the stop control, is APART from the start."""
    pts = [list(p) for p in pts]
    while len(pts) > 20 and (math.dist(pts[-1][:2], pts[0][:2]) < APART + STOP_BEYOND
                             or min(math.dist(pts[-1][:2], p[:2]) for p in pts[:12]) < APART):
        pts.pop()
    return pts


def main():
    stages = json.load(open(SRC, encoding="utf-8"))["stages"]
    for st in stages:
        pts = trimmed(st["points"])
        st = dict(st, points=pts, length=sum(math.dist(pts[i][:2], pts[i + 1][:2]) for i in range(len(pts) - 1)))
        tan = tangents(pts)
        base = os.path.join(OUT, st["id"])
        put(os.path.join(base, "race.race.json"), race(st, pts, tan))
        put(os.path.join(base, "rally", "drivelineSpline.json"), spline(st, pts, tan))
        nb = notebook(st, pts, tan)
        put(os.path.join(base, "rally", "notebooks", "structured.notebook.json"), nb)
        print("%s: %d nodes, %d pacenotes" % (st["id"], len(pts), len(nb["pacenotes"])))


if __name__ == "__main__":
    main()
