# Fog/Storm IoT Paper — `main.tex`

IEEE conference paper (double-column, `IEEEtran`) evaluating the distributed
fog architecture (8 gateways) vs. the centralized one (1 gateway) on Apache
Storm. Every measured metric is given a closed-form definition; figures embed
the real Grafana captures from `../img/`.

## How to compile

The `.tex` expects figures at `../img/` (already set via `\graphicspath`), so
keep it in `results/paper/` next to `results/img/`.

**Option A — Overleaf (easiest):**
Upload `results/paper/main.tex` together with the `results/img/` folder,
preserving the relative layout (`img/` one level up from `main.tex`, or adjust
`\graphicspath` to `{{img/}}` and put the images beside the `.tex`). Set the
compiler to **pdfLaTeX**.

**Option B — Local, with tectonic (self-contained, auto-downloads packages):**
```bash
brew install tectonic          # macOS
tectonic results/paper/main.tex
```

**Option C — Local, with a full TeX Live / MacTeX install:**
```bash
cd results/paper
pdflatex main.tex
pdflatex main.tex              # second pass resolves refs/citations
```

## Dependencies (all in TeX Live / MacTeX / Overleaf by default)
`IEEEtran`, `tikz`, `pgfplots`, `graphicx`, `booktabs`, `amsmath`, `amssymb`,
`subcaption`, `siunitx`, `xcolor`, `url`, `cite`, `algorithmic`.

## What's inside
- **3 TikZ diagrams** drawn natively: 3-tier architecture (Fig. 1), gateway
  topology (Fig. 2), cloud topology (Fig. 3), store-and-forward phases (Fig. 4).
- **2 pgfplots comparisons** from the table data: cloud complete latency vs N
  (log–log) and WAN vs N.
- **13 embedded Grafana PNGs** as evidence figures: monolithic baseline
  (`img/monolithic/` — bolt capacity 14.5, emitted, transferred); KB1-A/B
  saturation vs linear growth; KB2-A/B queue depth, ingestion continuity,
  capacity flood. **Upload `img/monolithic/` to Overleaf along with the kb* folders.**
- **Formula-defined metrics:** offered load, algebraic-equivalence aggregation,
  derived-window algebra, WAN reduction, EMA latency (α=0.2/0.3), bolt capacity,
  complete latency + M/M/1 lens, queue depth / drain rate / data loss.
- **16 verified references** (Bonomi 2012/2014, Storm@Twitter SIGMOD 2014,
  Satyanarayanan 2017, Shi 2016, Dastjerdi & Buyya 2016, Naha IEEE Access 2018,
  Yousefpour JSA 2019, Hong & Varghese CSUR 2019, R-Storm, T-Storm, A3-Storm,
  Dizdarević CSUR 2019, Naik ISSE 2017, Abdullah WCMC 2021, Paho).

## Provenance / integrity
All numbers match the measured KB1-A/B and KB2-A/B tables; the 18 derived ratios
(31.6×, 11.6×, 3.1×, recovery 71/101 s, Q_max 200/25, 21 JDBC conns, etc.) were
re-derived from the raw figures and checked to agree. The three architectural
limits (no connection pool, untracked trigger, flush stampede) were confirmed
against the Storm source in `fog-gateway/` and `fog-cloud/`.
