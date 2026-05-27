# fa18

A working model of a slice of the **F/A-18C Hornet Stores Management System (SMS)** —
the avionics that track what weapons are hung on the jet, let the pilot select them,
set how they come off, and command their release.

This is a **personal learning project**. The behavior being modeled is the SMS as it
appears in [DCS World (Digital Combat Simulator)](https://www.digitalcombatsimulator.com/).
The goal is to understand how the aircraft's systems actually work by re-implementing
their logic from scratch — and to do it in **Ada**, the language traditionally used for
real avionics software.

It is a *subset* of the real system: enough of the Stores page to be faithful to the
state machine and release gating, and nothing that would make it a flight-rated training
device. See [Scope](#scope) below.

## What it models

The code implements the cockpit **STORES page** — the Digital Display Indicator (DDI)
format the pilot uses to manage and employ weapons:

- **Stations 1–9** with a per-station state machine (`Empty → Loaded → Selected → Releasing`, plus `Jettison`).
- A small weapon catalog: `MK82` (bomb), `AIM9` / `AIM7` (missiles), `TANK` (fuel).
- **Release modes** — CCIP, CCRP, and RIPPLE (string quantity + ripple interval).
- The **Master Arm** safety interlock (SAFE / ARM / SIM) and the air-to-ground vs. air-to-air employment toggle.
- **Release logic and gating** — the pickle command, CCRP "release point reached" handoff, ripple burst sequencing, and selective jettison.
- **DDI pushbutton dispatch** — mapping the 20 physical bezel buttons to the events they raise in the current state.

The whole thing is built around a single **total reducer**:

```
function Apply (State : SMS_State; Event : Input_Event) return SMS_State;
```

Every state change flows through `Apply`. It never raises on bad input — an invalid
event returns the state unchanged with an advisory message. That keeps the model easy
to test and reason about.

## Layout

| Path | Purpose |
|------|---------|
| `src/sms.ads` / `src/sms.adb` | Core: domain types, event model, the `Apply` reducer, release gating, pushbutton dispatch. |
| `src/sms-render.ads` / `src/sms-render.adb` | Pure text renderer for the STORES DDI page (`State -> screen text`, never mutates). |
| `src/sms_demo.adb` | Runnable walkthrough of the spec's worked example (load, select, ripple, arm, commit), plus A/A and jettison demos. |
| `src/sms_tests.adb` | Assertion-based tests against the spec's state machine, invariants, and gating. Exits non-zero on failure. |
| `docs/sms-stores-page-spec.md` | The normative specification this code implements. |
| `fa18.gpr` | GPRbuild project file. |

The spec in `docs/` is the source of truth. The data model (§8), input event model (§9),
station state machine (§5), and release gating (§10) are treated as the normative
contract; the Ada code implements them and the tests check them.

## Building and running

Requires the **GNAT** Ada toolchain (`gprbuild`). On Debian/Ubuntu this is
`gnat` + `gprbuild`; alternatively use [Alire](https://alire.ada.dev/) (`alr`).

```sh
# build both executables into ./bin
gprbuild -P fa18.gpr

# run the worked-example demo (renders the STORES page at each step)
./bin/sms_demo

# run the test suite (exits non-zero if anything fails)
./bin/sms_tests
```

Build artifacts land in `obj/` and `bin/` (both gitignored).

## Scope

This is a functional proof-of-concept, **not** flight-rated software and not a training
device. Deliberately out of scope: real CCIP/CCRP ballistics and navigation, radar / IR
seeker / targeting-pod sensors, the full weapon catalog, true carriage and
weight-and-balance limits, hardware/1553-bus integration, HUD and other DDI formats, and
any airworthiness or live-arming behavior. The "LIVE" release is a logged event, not a
hardware command. See §12 of the spec for the full list.
