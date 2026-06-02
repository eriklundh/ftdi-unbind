# LIBWDI-API.md — the libwdi calls this tool uses

Reference for the `wdi_*` API surface the **unbind** direction depends on.
The **bind/restore** direction does **not** use libwdi — it uses
SetupAPI/CfgMgr32 (see `RESTORE-STRATEGY.md`). That asymmetry is the
single most important thing to understand before coding.

All signatures below are from libwdi v1.5.0 (`libwdi.h`). Confirm against
the actual header in your checkout — update this doc if it differs.

## Enumeration

```c
struct wdi_device_info {
    struct wdi_device_info *next;   // linked list
    unsigned short vid;             // vendor id
    unsigned short pid;             // product id
    bool is_composite;              // composite device?
    unsigned char mi;               // interface number if composite
    char *desc;                     // device description string
    char *driver;                   // current driver name, or NULL
    char *device_id;                // instance id
    char *hardware_id;              // hardware id
    char *compatible_id;
    char *upper_filter;
    unsigned long driver_version;
};

int  wdi_create_list(struct wdi_device_info **list,
                     struct wdi_options_create_list *options);
int  wdi_destroy_list(struct wdi_device_info *list);
```

- `wdi_options_create_list` lets you include *all* devices or only those
  without a driver, etc. For `--list` we want to see everything (so the
  current `driver` field is meaningful); for matching we filter ourselves.
- Walk the `next` chain, copy `{vid, pid, desc, device_id, driver}` into
  our plain `device_record` (the Phase 1 struct). Keeping our core on
  `device_record` rather than `wdi_device_info` is what makes the matcher
  unit-testable without libwdi.
- Always `wdi_destroy_list()` to free.

## Install (the unbind direction — install WinUSB)

```c
enum wdi_driver_type { WDI_WINUSB, WDI_LIBUSB0, WDI_LIBUSBK,
                       WDI_USER, WDI_NB_DRIVERS };

struct wdi_options_prepare_driver {
    enum wdi_driver_type driver_type;   // set to WDI_WINUSB
    char *vendor_name;
    char *device_guid;
    bool disable_cat;
    bool disable_signing;
    // ... see header
};

int  wdi_prepare_driver(struct wdi_device_info *device_info,
                        const char *path,           // temp dir for inf/cat
                        const char *inf_name,
                        struct wdi_options_prepare_driver *options);

int  wdi_install_driver(struct wdi_device_info *device_info,
                        const char *path,
                        const char *inf_name,
                        struct wdi_options_install_driver *options);

const char *wdi_strerror(int errcode);
bool wdi_is_driver_supported(enum wdi_driver_type type,
                             struct wdi_driver_info *info_out);
```

Flow for `ftdi-unbind`:
1. `wdi_create_list` → find the single `wdi_device_info*` whose vid/pid
   match (reuse the Phase 1 matcher on the adapted records, then map the
   chosen record back to its `wdi_device_info*`).
2. `wdi_prepare_driver(dev, tmp, "ftdi_winusb.inf", &opts)` with
   `opts.driver_type = WDI_WINUSB`. This autogenerates the inf + a signed
   catalog (libwdi self-signs with a generated cert) into `tmp`.
3. `wdi_install_driver(dev, tmp, "ftdi_winusb.inf", NULL)`. libwdi spawns
   an **elevated** installer; if our process isn't elevated this is where
   it matters — we check elevation *first* and error cleanly (Phase 3),
   rather than relying on libwdi's own elevation prompt.
4. Check the return; on non-zero, print `wdi_strerror(rc)`.

## Version / capability

```c
const char *wdi_get_version(void);   // or wdi_get_version_info — check header
```

Phase 0's probe calls this to prove the static link resolves.

## Elevation

libwdi can elevate its own installer step, but our design (see CLAUDE.md)
is to **require the tool itself be run elevated** and error clearly if
not, so behaviour is predictable and matches the "require elevation,
don't auto-relaunch" decision. Detect elevation with the standard Win32
token check (`OpenProcessToken` + `GetTokenInformation(TokenElevation)`).

## What libwdi does NOT do (so we don't reach for it wrongly)

- It does **not** reinstall a third-party vendor driver like FTDI's VCP.
  It installs WinUSB / libusb0 / libusbK / usbser / a user-supplied
  driver. Restoring the FTDI VCP is therefore a SetupAPI/CfgMgr32 job, not
  a libwdi job. See `RESTORE-STRATEGY.md`.
- It does **not** "uninstall" a driver to revert. Removal + re-enumeration
  is again SetupAPI/CfgMgr32.

Keep the libwdi dependency confined to the install (unbind) direction;
the restore (bind) direction is pure Win32.
