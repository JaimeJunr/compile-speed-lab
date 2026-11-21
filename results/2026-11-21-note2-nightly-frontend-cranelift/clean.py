# Média, mínimo e máximo do check/build do zero por projeto e configuração, a partir de clean.csv.
import csv, statistics as st, sys
from collections import defaultdict
rows = defaultdict(list)
for r in csv.DictReader(open(sys.argv[1])):
    rows[(r["project"], r["metric"], r["cfg"])].append(r)
for (p, m, c), rs in rows.items():
    ok = [float(r["seconds"]) for r in rs if r["rc"] == "0"]
    rss = max(int(r["maxrss_kb"]) for r in rs) // 1024
    falhas = len(rs) - len(ok)
    media = f"{st.mean(ok):6.1f}s [{min(ok):.1f}-{max(ok):.1f}]" if ok else "   —"
    print(f"{p:15} {m:5} {c:4} média={media} n={len(ok)} falhas={falhas} pico={rss}MB")
