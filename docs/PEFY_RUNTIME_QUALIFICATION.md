# PEFY OpenClaw Runtime Qualification

## Status

`PEFY-TECH/openclaw` is the registered default runtime for the PEFY Agent Workforce, but registration does **not** mean production qualification.

At the review performed on 2026-09-13:

- PEFY fork `main`: `316978700e24f7f14aab6b07fbbcaddd4dafe949` (2026-04-03);
- canonical source: `openclaw/openclaw`;
- declared license: MIT;
- measured drift: 0 PEFY-only commits and 68,324 upstream-only commits;
- drift classification: **U4 — major/unbounded production drift**;
- GitHub Actions runs visible on the PEFY fork: none;
- branch protection on PEFY `main`: not enabled at review time.

This baseline must therefore remain **not production-qualified** until the controlled rebaseline below is completed.

## Mandatory rebaseline rule

Do not bulk-sync, blindly rebase, automatically upgrade, or merge upstream solely to reach parity. A large upstream delta can contain breaking changes, dependency changes, new data flows, new model/tool permissions, security regressions, changed licensing in subcomponents, migrations or altered operational assumptions.

The PEFY process is:

`verify source -> pin candidate -> measure drift -> review provenance/license -> security/advisory review -> inspect breaking changes -> run CI/tests -> benchmark -> validate PEFY adapters/policies -> stage -> runtime smoke -> rollback proof -> approve`

## Canonical source and license

Canonical upstream is:

```text
https://github.com/openclaw/openclaw
```

The fork currently exposes an MIT `LICENSE`. Qualification must still review third-party dependencies and bundled assets independently; repository-level MIT licensing does not automatically qualify every transitive dependency or external service.

## Drift measurement

Run from a clean candidate checkout:

```bash
bash scripts/pefy-runtime-rebaseline.sh
```

For a reproducible review, pin the upstream SHA after the reviewer selects it:

```bash
PEFY_EXPECTED_UPSTREAM_SHA="<reviewed-upstream-sha>" \
  bash scripts/pefy-runtime-rebaseline.sh
```

The script:

- fetches canonical upstream into a dedicated non-branch ref;
- never merges, rebases, resets or checks out upstream;
- records PEFY-only and upstream-only commit counts;
- classifies drift U0-U4;
- confirms the expected MIT license marker;
- records license hashes and candidate SHAs;
- fails qualification for U4 drift;
- writes non-secret evidence under `artifacts/pefy-openclaw-rebaseline/`.

## U0-U4 interpretation

| Class | Upstream-only commits | Default treatment |
| --- | ---: | --- |
| U0 | 0 | parity; normal qualification |
| U1 | 1-99 | focused change review |
| U2 | 100-999 | structured compatibility/security review |
| U3 | 1,000-9,999 | major rebaseline programme |
| U4 | 10,000+ | freeze production promotion; controlled rebaseline required |

Commit count is a drift signal, not a risk score by itself. A single security-critical change may be more important than thousands of low-impact commits.

## Security qualification

Before accepting a new baseline:

- inspect security-relevant changes since the PEFY base;
- review CVE/GHSA/OSV/vendor advisories and CISA KEV where applicable;
- run repository CodeQL/security workflows;
- scan dependency locks and container/package outputs;
- verify secret-detection policy remains active;
- verify execution approvals remain least privilege;
- test deny/approval-gated paths, not only allowed paths;
- verify model/provider/tool routing does not bypass PEFY governance;
- verify no new telemetry or remote service silently violates sovereignty policy;
- verify data-retention and storage changes;
- record accepted residual risk.

## Compatibility qualification

Test PEFY integrations against the exact candidate:

- Mission Control gateway/runtime compatibility;
- ClawTeam skill and concrete-agent execution allowlists;
- PEFY ΩOmniRoute / adapter expectations where integrated;
- PEFY ΩCSF security controls;
- PEFY ΩESF skill loading and isolation;
- observability/audit hooks;
- tenant/context propagation;
- offline/on-prem operation where required;
- update and deterministic rollback.

## CI gate

Production promotion requires actual GitHub Actions evidence for the exact PEFY candidate SHA. The presence of workflow files is not evidence that workflows ran.

Required categories include at least:

- repository CI;
- install smoke;
- workflow sanity;
- CodeQL/security scanning;
- PEFY rebaseline gate;
- package/container checks relevant to the selected deployment form.

If GitHub Actions remains disabled or produces no run, the gate stays **BLOCKED**.

## Benchmark gate

Before replacing the currently selected PEFY runtime baseline, record evidence for:

- functional correctness;
- latency and throughput for representative missions;
- resource use;
- reliability/recovery;
- security behavior;
- compatibility with Mission Control and ClawTeam;
- offline/on-prem capability where required;
- operational complexity;
- rollback time.

A newer upstream version is not automatically better for PEFY.

## Runtime acceptance

Only after code qualification, run on the real approved host:

1. verify OpenClaw version and immutable source/artifact identity;
2. verify gateway health;
3. verify production credentials are injected without repository exposure;
4. verify concrete agent approval policies;
5. verify ClawTeam skill and executable rules;
6. run the ClawTeam production qualifier;
7. run a controlled multi-agent mission;
8. prove one allowed action succeeds;
9. prove one disallowed or approval-gated action is blocked/routed correctly;
10. confirm logs and audit evidence;
11. confirm rollback to the previous known-good runtime.

## Promotion states

- **Registered:** repository known to PEFY.
- **Rebaseline blocked:** source or drift requires review.
- **Code qualified:** exact candidate passed controlled rebaseline + CI/security/benchmark gates.
- **Runtime qualified:** exact candidate passed real-host controls.
- **Live production active:** runtime-qualified candidate is deployed with smoke, monitoring and rollback evidence.

The current fork remains **rebaseline blocked** until the U4 condition is resolved through the controlled process above.
