# Recovery V2 TODO

- Wire Recovery V2 trend rows to bridge-backed daily recovery, HRV, and resting HR series when the bridge exposes trusted daily values.
- Replace the zero vitals cards with trusted packet-derived respiratory rate, SpO2, and wrist-temperature fields once their semantics are verified.
- Add a real recovery timeline model that links the score to the primary sleep window and the packet/vitals inputs used by the score run.
- Add Recovery V2 snapshot tests or simulator screenshots for no-data, bridge-data, and packet-run-blocked states.
- Keep Recovery V2 free of fixture/sample values; show `0` or an empty state until trusted local data exists.
