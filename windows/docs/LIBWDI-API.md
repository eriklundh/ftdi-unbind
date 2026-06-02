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

Flow for `ftdi-unbind` (implemented in `src/install.c`):

1. The caller (`main.c`) already holds a matched `device_record`
   (vid, pid, device_id) from Phase 2 enumeration. `install_winusb()`
   takes those three values.
2. `install_winusb` calls `wdi_create_list` a second time with
   `list_all=TRUE` to obtain a fresh `wdi_device_info*` list whose nodes
   stay alive through the install. Walk the list to find the node whose
   `vid`, `pid`, and `device_id` all match exactly.
3. Build a temp dir path: `GetTempPathA` returns `%TEMP%\` (with trailing
   backslash); append `ftdi_winusb_<pid>` and `CreateDirectoryA`. libwdi
   writes the generated `.inf` and self-signed `.cat` there.
4. `wdi_prepare_driver(dev, tmp, "ftdi_winusb.inf", &opts)` with
   `opts.driver_type = WDI_WINUSB`. Autogenerates the inf + signed catalog
   (libwdi self-signs with a per-run generated cert) into `tmp`.
5. `wdi_install_driver(dev, tmp, "ftdi_winusb.inf", NULL)`. libwdi spawns
   an elevated installer subprocess; the elevation check in `main.c` fires
   *before* this call so the failure mode is our clear error message, not
   a surprise UAC dialog.
6. `wdi_destroy_list(list)` — always called, including on error paths.
7. Check the return; on non-zero, print `wdi_strerror(rc)`.

The temp dir (`%TEMP%\ftdi_winusb_<pid>`) is not deleted after install —
it holds the generated `.inf`/`.cat` and is cleaned up by the OS temp
policy. This is consistent with Zadig's behaviour.

## Version / capability

```c
int         wdi_get_wdf_version(void);    // returns WDF_VER (e.g. 1011)
const char *wdi_strerror(int errcode);    // human-readable error string
```

`wdi_get_version()` does **not** exist in v1.5.0 — there is no library-version
function.  Phase 0's probe uses `wdi_get_wdf_version()` + `wdi_strerror(0)`
to prove the static link resolves and the embedded payload is present.

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

## Known libwdi v1.5.0 issue (upstream #368)

`wdi_is_driver_supported(WDI_WINUSB)` returns `FALSE` when `WDK_DIR` is
undefined, causing silent fallback to usbser (Generic USB CDC). Fix and
`winusb.inf.in` co-installer patch documented in `BUILD-ENVIRONMENT.md`.
Upstream: https://github.com/pbatard/libwdi/issues/368
