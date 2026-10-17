"""Rally stages for West Coast USA (sl_rally, #24): python tools/make_rally.py

The level has no rally stages of its own (no pacenote notebooks, no stage missions), only dirt and gravel decal roads. This picks four of the long ones
(400-800 m, gravel or dirt, not the invisible/rubber/erosion decals), spreads the starts apart, smooths each node list into a line (Catmull-Rom) sampled every
5 m, and writes mod/street_legal/rally/west_coast_usa.json: { stages: [ { id, name, points: [[x, y, z]], width, length } ] }.
sl_rally calls the corners from the line's curvature (sl/core/rally.pacenotes).
"""
import json
import math
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "mod", "street_legal", "rally", "west_coast_usa.json")
LEVEL = r"I:\SteamLibrary\steamapps\common\BeamNG.drive\content\levels\west_coast_usa.zip"
GOOD = ("road_gravel", "road_dirt")            # material prefixes that are real driving surface
SKIP = ("road_invisible", "track_rubber", "bank_erosion")
NAMES = ["Gravel Ridge", "Dirt Track Circuit", "Back Country Loop", "High Gravel"]
STEP = 5.0


def catmull(points, step):
    """The line through the nodes (centripetal-ish uniform Catmull-Rom), resampled every `step` metres."""
    p = [points[0]] + points + [points[-1]]
    dense = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(20):
            t = k / 20
            dense.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                      + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(3)))
    dense.append(tuple(points[-1]))
    out, acc, last = [dense[0]], 0.0, dense[0]
    for q in dense[1:]:
        d = math.dist(q[:2], last[:2])
        acc += d
        last = q
        if acc >= step:
            out.append(q)
            acc = 0.0
    if math.dist(out[-1][:2], dense[-1][:2]) > 1:
        out.append(dense[-1])
    return out


def length(points):
    return sum(math.dist(points[i][:2], points[i + 1][:2]) for i in range(len(points) - 1))


def main():
    z = zipfile.ZipFile(LEVEL)
    roads = []
    for n in z.namelist():
        if "dirt_decalroads" in n and n.endswith(".level.json"):
            for line in z.read(n).decode("utf-8", "ignore").splitlines():
                if '"DecalRoad"' not in line:
                    continue
                d = json.loads(line)
                mat = d.get("material") or ""
                nodes = d.get("nodes") or []
                if len(nodes) < 6 or mat.startswith(SKIP) or not mat.startswith(GOOD):
                    continue
                pts = [tuple(nd[:3]) for nd in nodes]
                L = length(pts)
                if 400 <= L <= 900:
                    roads.append((L, pts, [nd[3] if len(nd) > 3 else 6 for nd in nodes], mat))
    roads.sort(key=lambda r: -r[0])
    chosen = []
    for L, pts, widths, mat in roads:
        if all(math.dist(pts[0][:2], c[1][0][:2]) > 250 and math.dist(pts[-1][:2], c[1][-1][:2]) > 250 for c in chosen):
            chosen.append((L, pts, widths, mat))
        if len(chosen) == 4:
            break
    stages = []
    for i, (L, pts, widths, mat) in enumerate(chosen):
        line = catmull(pts, STEP)
        stages.append({"id": "wcusa_rally_%d" % (i + 1), "name": NAMES[i], "points": [[round(c, 1) for c in q] for q in line],
                       "width": round(sum(widths) / len(widths), 1), "length": round(length(line)), "surface": mat})
        print(stages[-1]["id"], stages[-1]["name"], stages[-1]["length"], "m,", len(line), "points,", mat, pts[0][:2], "->", pts[-1][:2])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"stages": stages}, open(OUT, "w"), separators=(",", ":"))
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
