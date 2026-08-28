# Pipeline Watch

Monitors active Python/R training jobs, Quarto renders, and data pipelines
from the bar: live CPU/RAM per matched process, and a desktop notification
(plus optional sleep-inhibit) when one finishes.

## Install

```bash
omarchy plugin add https://github.com/Ch3w3y/omarchy-pipeline-watch.git --enable
```

`scanner.py` polls `ps` and classifies each process by matching keywords in
its command line (`torch`, `xgboost`, `train`, `fit`, `polars`, `duckdb`,
`pandas`, `sklearn`, a Jupyter kernel, a DuckDB CLI session, Quarto
rendering, …) — pure Python standard library plus whatever's already on a
default Omarchy install (`ps`, `notify-send`). Nothing extra to install.
