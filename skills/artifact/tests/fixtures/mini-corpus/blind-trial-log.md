# Synthetic blind-trial log

Test input for `test-goal-gate.sh`: the machine block `goal_gate.blind_records()`
parses, with invented runs. The real log lives in the corpus, outside this repo.

<!-- BLIND-TRIAL-VERDICTS v1 runs=3 -->
```verdicts
run=r1 spec=one.spec.md verb=add-item build1=OK build2=OK handwritten-html=no verdict=pass
run=r2 spec=two.spec.md verb=decide build1=OK build2=OK handwritten-html=no verdict=pass
run=r3 spec=three.spec.md verb=decide,new-round build1=OK build2=OK handwritten-html=no verdict=pass
```
