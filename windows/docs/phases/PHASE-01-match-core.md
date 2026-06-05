# PHASE-01-match-core.md — Pure core: VID:PID parse + matching (TDD)

Branch: `phase/01-match-core`

## Goal

The pure, hardware-free logic, developed strictly test-first. No libwdi,
no Windows driver APIs. It operates on a plain `device_record` struct, so
the unit tests run anywhere — including CI with no Windows and no device.
This is where the project's real TDD lives.

## Files

```
src/match.h          # device_record, vidpid_parse, match_devices
src/match.c
src/args.h           # options struct, parse_args, exit codes
src/args.c
tests/test_match.c   # CTest executable
tests/test_args.c    # CTest executable
```

`device_record`:
```c
typedef struct {
    unsigned short vid;
    unsigned short pid;
    const char *desc;        // borrowed
    const char *device_id;   // borrowed
    const char *driver;      // borrowed, may be NULL
} device_record;
```

## Red → green → refactor

### 1. vidpid_parse

```c
// returns 0 on success; nonzero on malformed input
int vidpid_parse(const char *arg, unsigned short *vid, unsigned short *pid);
```
Test first (`tests/test_match.c`): accepts `0403:6015`, `0x0403:0x6015`,
`403:6015`; normalises case; rejects missing colon, non-hex, >4 hex
digits, empty. Then implement to green.

### 2. match_devices

```c
// fills out_idx[] with indices of records matching vid&&pid; returns count
int match_devices(const device_record *recs, int n,
                  unsigned short vid, unsigned short pid,
                  int *out_idx, int out_cap);
```
Test first: strict VID&&PID equality; 0, 1, and >1 matches (ambiguity);
non-matching VID or PID excluded. Implement to green.

### 3. args + exit codes

```c
typedef enum { ACTION_UNBIND, ACTION_BIND } action_t;
typedef struct { action_t action; const char *vidpid;
                 int dry_run; int all; int help; } options;
int parse_args(int argc, char **argv, action_t action, options *opt);

// exit codes (match the Linux scripts):
#define EXIT_OK        0
#define EXIT_NOMATCH   1   // no device, or ambiguous without --all
#define EXIT_USAGE     2
```
Test first: `--dry-run`, `--all`, `-h/--help`, unknown flag → usage,
missing VID:PID → usage. Implement to green.

## Commits

- `test(match): vidpid_parse accepts/normalises/rejects forms`
- `feat(match): implement vidpid_parse`
- `test(match): strict matching + ambiguity detection`
- `feat(match): implement device matching`
- `test(cli): argument + exit-code model`
- `feat(cli): implement arg parsing`
- `refactor(core): tidy and document the public core API`

## Acceptance

- [ ] `ctest` green; covers normalisation, rejection, match, ambiguity,
      arg parsing, exit codes
- [ ] `match.c` / `args.c` compile with **no** libwdi or Windows-driver
      dependency (prove it: a tiny host build, or MSVC without linking
      libwdi)
- [ ] Same inputs produce the same decisions as the Linux scripts
- [ ] Branch merged to `main`

## Why this matters

This is the layer that makes the tool *safe* — strict matching and
ambiguity refusal are the whole reason it beats Zadig. Getting it under
test, test-first, means the safety guarantees are verified, not hoped
for. Everything in Phases 2–4 builds on this core.
