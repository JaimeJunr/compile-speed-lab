# Mediana e desvio do rebuild incremental a partir do JSON do hyperfine 2 (schema_version 2).
import json, statistics as st, sys
for path in sys.argv[1:]:
    res = json.load(open(path))["results"][0]
    wall = [m["time_wall_clock"]["value"] for m in res["measurements"]]
    print(f'{res["name"]:5} mediana={st.median(wall):.2f}s desvio={st.stdev(wall):.2f}s n={len(wall)}  {path}')
