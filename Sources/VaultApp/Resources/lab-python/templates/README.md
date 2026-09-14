# First experiment

Open the notebooks in order. They execute locally, including the Metal training notebook.

The supplied baseline.py is the curriculum Starter Lab, copied without modification.

Console:

```
python baseline.py --self-check
python baseline.py --out runs/baseline-01 --seed 7 --events 800
pytest -q
git init
git add .
git commit -m "First experiment"
```

Each execution saves a record under runs/. The Python session shares variables between cells. Clear session removes user variables; it does not unload native packages.
