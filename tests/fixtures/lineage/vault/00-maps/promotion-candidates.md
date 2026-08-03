# Promotion candidates

Notes that have cleared the maturity bar but haven't been promoted yet.
Evidence = number of entries in each note's `repos:` list.

- `idea` → `trialing`: observed in **2+** repos
- `trialing` → `enforced`: observed in **3+** repos

```dataview
TABLE maturity, length(repos) AS "repos", last-reviewed
FROM "practices"
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
SORT length(repos) DESC
```
