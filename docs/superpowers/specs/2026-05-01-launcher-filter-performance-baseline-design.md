# Launcher Filter Performance Baseline Design

## Goal

Protect the restored launcher list and filter responsiveness with a repeatable SwiftPM/XCTest performance gate. The gate should measure the app search filter directly, compare the result against a committed baseline, and report a comfort band so performance changes are visible during normal verification.

## Scope

This first version covers only `LiquidGlassLauncherModel.filter(_:normalizedQuery:)`.

It does not measure full launcher window presentation, SwiftUI rendering, scrolling, icon loading, app indexing, or end-to-end visual latency. Those are valid future profiling targets, but the immediate regression came from list/filter behavior and should be guarded with the smallest stable measurement first.

## Architecture

- Add a checked-in baseline file at `.agents/performance/launcher-filter-baseline.json`.
- Add a focused XCTest case, `LauncherFilterPerformanceTests`, under `Tests/BuckyTests`.
- Add a small in-test benchmark harness that:
  - builds deterministic `LaunchItem` fixtures,
  - runs warmup iterations before measurement,
  - measures repeated representative filter queries,
  - summarizes sample durations,
  - compares the current summary to the baseline,
  - prints current metric, baseline metric, percent delta, and comfort band.
- Add a `make perf` target that runs only the launcher filter performance test.
- Keep `swift test` as the complete local verification path; the performance test should run there too.

The benchmark uses direct model logic instead of launching the app. That keeps it fast, deterministic enough for CI, and isolated from macOS UI scheduling noise.

## Metric

The primary metric is elapsed wall-clock time for one representative workload:

1. Generate a deterministic set of synthetic launch items.
2. Run a fixed sequence of normalized queries that exercises blank results, prefix matches, multi-token matches, and sparse matches.
3. Repeat the query sequence enough times to create a measurable duration.
4. Collect multiple samples after warmup.
5. Compare the median sample duration against the checked-in baseline median.

The JSON should store at least:

- benchmark name
- baseline duration in milliseconds
- sample count
- workload item count
- workload query count
- comfort threshold percent
- regression threshold percent
- date captured
- git commit used when captured, if available

Median is preferred over minimum because the user-visible concern is sustained responsiveness, not best-case timing. The test may also print the fastest and slowest sample for context, but the pass/fail decision uses the median.

## Comfort Bands

The test always reports the delta from baseline:

- `comfort`: current median is no more than 5 percent slower than baseline.
- `watch`: current median is more than 5 percent and no more than 15 percent slower than baseline.
- `regression`: current median is more than 15 percent slower than baseline.

Only `regression` fails the test. Faster results should pass and report a negative delta.

## Baseline Update Workflow

Baseline updates must be explicit. The test must never rewrite the baseline file during a normal `swift test` run.

Operator workflow:

1. Start from a clean worktree.
2. Build and test the intended performance state.
3. Run the focused performance command several times:

   ```bash
   make perf
   ```

4. If the reported numbers are stable and the new behavior is intentionally accepted, run the explicit baseline capture command:

   ```bash
   make perf-baseline
   ```

5. Review the JSON diff in `.agents/performance/launcher-filter-baseline.json`.
6. Run `make perf` again to confirm the captured baseline is accepted.
7. Commit the code change and baseline JSON together when the performance profile intentionally changed.

`make perf-baseline` should set an environment variable consumed by the XCTest process, such as `BUCKY_PERF_UPDATE_BASELINE=1`. The test harness should only write the baseline file when that variable is present.

## Error Handling

- Missing baseline during normal test runs: fail with a clear message that tells the developer to run `make perf-baseline`.
- Malformed baseline JSON: fail with the file path and decoding error.
- Baseline write failure during explicit capture: fail with the file path and write error.
- Unsupported platform or unavailable clock APIs: fail clearly instead of silently skipping.
- Very small or zero baseline duration: fail as invalid baseline data.

## Security And Resource Constraints

- The benchmark uses synthetic in-memory data only.
- It does not scan the filesystem, launch apps, call network APIs, or write outside the repo.
- Normal test runs are read-only with respect to baseline data.
- Baseline update writes only `.agents/performance/launcher-filter-baseline.json`.

## Testing

Add tests that prove:

- The performance result comparator classifies `comfort`, `watch`, and `regression` correctly.
- A missing or malformed baseline produces a clear failure path.
- Explicit baseline encoding includes the expected metric fields.
- The end-to-end performance XCTest runs the restored filter workload and compares against the baseline.

The implementation should follow test-first order for comparator and baseline encoding logic. The final verification command is:

```bash
swift test
```

The focused performance command is:

```bash
make perf
```

The explicit baseline capture command is:

```bash
make perf-baseline
```
