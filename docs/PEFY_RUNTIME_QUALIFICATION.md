# PEFY OpenClaw Runtime Qualification

## Status

`PEFY-TECH/openclaw` is the registered default runtime for the PEFY Agent Workforce, but registration does **not** mean production qualification.

At the review performed on 2026-09-13:

- PEFY fork `main`: `316978700e24f7f14aab6b07fbbcaddd4dafe949` (2026-04-03);
- canonical source: `openclaw/openclaw`;
- repository license: MIT;
- initial measured divergence: 0 PEFY-only commits and 68,324 upstream-only commits;
- overall review class: **R4 — major/unbounded rebaseline drift**;
- GitHub Actions runs visible on the PEFY fork at the initial review: none;
- branch protection on PEFY `main` was not enabled at the initial review.

This baseline must therefore remain **not production-qualified** until the controlled rebaseline below is completed.

## Mandatory rebaseline rule

Do not bulk-sync, blindly rebase, automatically upgrade, or merge upstream solely to reach parity. A large upstream delta can contain breaking changes, dependency changes, new data flows, new model/tool permissions, security regressions, changed licensing in subcomponents, migrations or altered operational assumptions.

The PEFY process is:

`verify canonical source -> pin candidate -> measure upstream and downstream divergence -> verify repository license text -> security/advisory review -> inspect breaking changes -> run CI/tests -> benchmark -> validate PEFY adapters/policies -> stage -> runtime smoke -> rollback proof -> approve`

## Canonical source and license

The only canonical upstream accepted by the qualification script is:

```text
https://github.com/openclaw/openclaw.git
```

A caller-provided non-canonical upstream is rejected. Evidence records the canonical source identity explicitly.

Repository-level MIT evidence is also fail-closed: both the PEFY candidate and canonical upstream `LICENSE` files must match the approved standard MIT body and must be identical to one another before the script emits `spdx=MIT`. Hashes are generated with Python `hashlib` for Linux/macOS portability.

This repository-level check does not qualify every transitive dependency, embedded asset or external service. Those remain separate supply-chain gates.

## Drift measurement

Run from a clean candidate checkout:

```bash
bash scripts/pefy-runtime-rebaseline.sh
```

For a reproducible qualification review, pin the upstream SHA after the reviewer selects it:

```bash
PEFY_EXPECTED_UPSTREAM_SHA="<reviewed-upstream-sha>" \
  bash scripts/pefy-runtime-rebaseline.sh
```

The script:

- fetches only the canonical upstream into a dedicated non-branch ref;
- never merges, rebases, resets or checks out upstream;
- records PEFY-only and upstream-only commit counts;
- classifies upstream drift as `U0-U4`;
- classifies downstream divergence as `D0-D4`;
- calculates an overall review class `R0-R4` using the more severe of the two dimensions;
- verifies the standard MIT license body on both candidates and requires downstream/upstream equality;
- records canonical source, license hashes and candidate SHAs;
- fails normal qualification for `R4` drift;
- writes non-secret evidence under `artifacts/pefy-openclaw-rebaseline/`.

### Evidence-only workflow

The GitHub workflow is deliberately named **`PEFY Rebaseline Evidence (NON-QUALIFYING)`**. It runs the script with:

```text
PEFY_REBASELINE_REPORT_ONLY=1
```

A green result from that workflow means only that evidence was generated correctly and without upstream mutation. It **must never** be used as a branch-protection or promotion check that implies runtime/code qualification. The uploaded artifact is also labeled `NON-QUALIFYING`.

## U/D/R interpretation

Each dimension uses the same magnitude bands:

| Level | Commit-count range | Default treatment |
| --- | ---: | --- |
| 0 | 0 | no divergence on that dimension |
| 1 | 1-99 | focused change review |
| 2 | 100-999 | structured compatibility/security review |
| 3 | 1,000-9,999 | major rebaseline programme |
| 4 | 10,000+ | freeze production promotion; controlled rebaseline required |

`U#` represents upstream-only drift. `D#` represents PEFY/downstream-only divergence. `R#` is the overall review class and equals the more severe level of `U#` or `D#`.

Therefore `U0` alone must not be described as parity when downstream divergence exists. True parity requires `U0 + D0`, which yields `R0`.

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
- a **qualifying** PEFY rebaseline/drift decision, separate from the non-qualifying evidence-only workflow;
- package/container checks relevant to the selected deployment form.

If a required workflow is disabled, queued indefinitely, skipped without accepted rationale, or produces no run for the exact candidate, the gate stays **BLOCKED**.

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
- **Code qualified:** exact candidate passed controlled rebaseline plus CI/security/benchmark gates.
- **Runtime qualified:** exact candidate passed real-host controls.
- **Live production active:** runtime-qualified candidate is deployed with smoke, monitoring and rollback evidence.

The current fork remains **rebaseline blocked** until the R4 condition is resolved through the controlled process above.
