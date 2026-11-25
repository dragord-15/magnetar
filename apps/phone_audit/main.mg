// phone_audit/main.mg - Defensive security audit for an Android phone over USB
// Reads exposed settings/properties via ADB and reports risky configuration.
// Only for devices you own or are explicitly authorized to audit.
// Build: ./magc phone_audit/main.mg -o build/phone_audit
// Run:   ./build/phone_audit [--min-patch YYYY-MM-DD]

use "lib/adb.mg";
use "lib/string.mg";

extern fn print_str(string s) -> void;

const int SEV_OK = 0;
const int SEV_INFO = 1;
const int SEV_WARN = 2;
const int SEV_HIGH = 3;

static int G_OK = 0;
static int G_INFO = 0;
static int G_WARN = 0;
static int G_HIGH = 0;

fn pa_finding(int sev, string title, string detail) -> void {
    if (sev == SEV_OK) { print_str("  [OK]   "); G_OK = G_OK + 1; }
    else if (sev == SEV_INFO) { print_str("  [INFO] "); G_INFO = G_INFO + 1; }
    else if (sev == SEV_WARN) { print_str("  [WARN] "); G_WARN = G_WARN + 1; }
    else { print_str("  [HIGH] "); G_HIGH = G_HIGH + 1; }
    print_str(title);
    print_str("\n          ");
    print_str(detail);
    print_str("\n");
}

fn pa_line(string label, string value) -> void {
    print_str("  ");
    print_str(label);
    print_str(": ");
    if (str_is_empty(value)) { print_str("(unknown)"); }
    else { print_str(value); }
    print_str("\n");
}

fn pa_shell_trim(string cmd) -> string {
    string txt = adb_shell(cmd);
    char* p = cast<char*>(txt);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    int start = 0;
    while (start < n) {
        int c = cast<int>(*(p + start));
        if (c < 0) { c = c + 256; }
        if (c == 32 || c == 9 || c == 10 || c == 13) { start = start + 1; }
        else { break; }
    }
    int end = n;
    while (end > start) {
        int c = cast<int>(*(p + end - 1));
        if (c < 0) { c = c + 256; }
        if (c == 32 || c == 9 || c == 10 || c == 13) { end = end - 1; }
        else { break; }
    }
    int len = end - start;
    char* out = alloc<char>(len + 1);
    int i = 0;
    while (i < len) { *(out + i) = *(p + start + i); i = i + 1; }
    *(out + len) = 0;
    return cast<string>(out);
}

fn pa_first_int(string v) -> int {
    char* p = cast<char*>(v);
    int n = str_len(v);
    int i = 0;
    while (i < n && is_digit(*(p + i)) == false) { i = i + 1; }
    int val = 0;
    while (i < n && is_digit(*(p + i))) {
        val = val * 10 + cast<int>(*(p + i) - '0');
        i = i + 1;
    }
    return val;
}

fn pa_mount_writable(string target) -> bool {
    string mounts = adb_shell("mount");
    char* p = cast<char*>(mounts);
    char* t = cast<char*>(target);
    int n = str_len(mounts);
    int tl = str_len(target);
    int i = 0;
    while (i + tl < n) {
        int same = 1;
        int j = 0;
        while (j < tl) {
            if (*(p + i + j) != *(t + j)) { same = 0; break; }
            j = j + 1;
        }
        if (same == 1) {
            int e = i + tl;
            while (e < n && *(p + e) != '\n' && e < i + tl + 160) {
                if (*(p + e) == 'r' && *(p + e + 1) == 'w' && *(p + e + 2) == ',') {
                    return true;
                }
                e = e + 1;
            }
        }
        i = i + 1;
    }
    return false;
}

fn pa_is_on(string v) -> bool {
    if (str_equals(v, "1")) { return true; }
    return str_equals_ignore_case(v, "true");
}

fn pa_audit_identity() -> void {
    print_str("\n[1] Device identity\n");
    pa_line("serial", adb_device_serial());
    pa_line("model", adb_get_prop("ro.product.model"));
    pa_line("manufacturer", adb_get_prop("ro.product.manufacturer"));
    pa_line("android", adb_get_prop("ro.build.version.release"));
    pa_line("sdk", adb_get_prop("ro.build.version.sdk"));
    pa_line("security patch", adb_get_prop("ro.build.version.security_patch"));
    pa_line("build type", adb_get_prop("ro.build.type"));
    pa_line("fingerprint", adb_get_prop("ro.build.fingerprint"));
}

fn pa_audit_exposure() -> void {
    print_str("\n[2] Debug and network exposure\n");

    string usbdbg = pa_shell_trim("settings get global adb_enabled");
    if (pa_is_on(usbdbg)) {
        pa_finding(SEV_WARN, "USB debugging is enabled",
                   "Required for this audit; disable it in Developer options when finished.");
    } else {
        pa_finding(SEV_OK, "USB debugging is disabled",
                   "No ADB access is offered over the USB link.");
    }

    string wifidbg = pa_shell_trim("settings get global adb_wifi_enabled");
    if (pa_is_on(wifidbg)) {
        pa_finding(SEV_HIGH, "Wireless debugging is enabled",
                   "ADB is reachable over the network. Turn off Wireless debugging now.");
    } else {
        pa_finding(SEV_OK, "Wireless debugging is disabled",
                   "ADB is not exposed over Wi-Fi.");
    }

    string devopt = pa_shell_trim("settings get global development_settings_enabled");
    if (pa_is_on(devopt)) {
        pa_finding(SEV_INFO, "Developer options are enabled",
                   "Review the toggles and turn Developer options off when not needed.");
    } else {
        pa_finding(SEV_OK, "Developer options are disabled",
                   "No developer settings are active.");
    }
}

fn pa_audit_installs() -> void {
    print_str("\n[3] App installation policy\n");

    string unknown = pa_shell_trim("settings get secure install_non_market_apps");
    if (pa_is_on(unknown)) {
        pa_finding(SEV_WARN, "Installation from unknown sources is allowed",
                   "Android 8+ controls this per app; review Install unknown apps in Settings.");
    } else {
        pa_finding(SEV_OK, "Unknown sources are blocked",
                   "Apps can only be installed from trusted stores.");
    }

    string a11y = pa_shell_trim("settings get secure enabled_accessibility_services");
    if (str_is_empty(a11y) || str_equals(a11y, "null")) {
        pa_finding(SEV_OK, "No accessibility services enabled",
                   "No app holds an accessibility service that can observe the screen.");
    } else {
        pa_finding(SEV_WARN, "Accessibility services are enabled",
                   "Enabled: " + a11y + ". Review in Settings > Accessibility.");
    }
}

fn pa_audit_platform(string min_patch) -> void {
    print_str("\n[4] Platform hardening\n");

    string boot = str_trim(adb_get_prop("ro.boot.verifiedbootstate"));
    if (str_equals_ignore_case(boot, "green")) {
        pa_finding(SEV_OK, "Verified boot is green",
                   "Boot chain is locked and verified.");
    } else if (str_equals_ignore_case(boot, "orange")) {
        pa_finding(SEV_HIGH, "Bootloader is unlocked",
                   "Verified boot is broken; device integrity cannot be trusted.");
    } else if (str_equals_ignore_case(boot, "yellow")) {
        pa_finding(SEV_WARN, "Verified boot is yellow",
                   "A custom OS or unsigned component may be installed.");
    } else {
        pa_finding(SEV_INFO, "Verified boot state unavailable",
                   "The device did not report ro.boot.verifiedbootstate.");
    }

    string btype = str_trim(adb_get_prop("ro.build.type"));
    if (str_equals(btype, "user")) {
        pa_finding(SEV_OK, "Production build (user)",
                   "Release firmware is in use.");
    } else if (str_equals(btype, "userdebug") || str_equals(btype, "eng")) {
        pa_finding(SEV_HIGH, "Engineering/test firmware",
                   "Debug builds weaken isolation and often ship with root access.");
    } else {
        pa_finding(SEV_INFO, "Build type unavailable",
                   "The device did not report ro.build.type.");
    }

    string selinux = pa_shell_trim("getenforce");
    if (str_equals_ignore_case(selinux, "Enforcing")) {
        pa_finding(SEV_OK, "SELinux is enforcing",
                   "Mandatory access control is active.");
    } else if (str_equals_ignore_case(selinux, "Permissive")) {
        pa_finding(SEV_HIGH, "SELinux is permissive",
                   "SELinux violations are only logged, not blocked.");
    } else {
        pa_finding(SEV_INFO, "SELinux state unavailable",
                   "getenforce did not return a usable value.");
    }

    string idout = pa_shell_trim("id");
    if (str_contains(idout, "uid=0")) {
        pa_finding(SEV_HIGH, "ADB shell is running as root",
                   "Any USB-connected process can gain full device control.");
    } else {
        pa_finding(SEV_OK, "ADB shell is unprivileged",
                   "The shell user does not have root privileges.");
    }

    string crypto = str_trim(adb_get_prop("ro.crypto.state"));
    if (str_equals_ignore_case(crypto, "encrypted")) {
        pa_finding(SEV_OK, "Storage is encrypted",
                   "File-based/disk encryption is active.");
    } else {
        pa_finding(SEV_WARN, "Encryption state not confirmed",
                   "The device did not report ro.crypto.state=encrypted.");
    }

    string patch = str_trim(adb_get_prop("ro.build.version.security_patch"));
    if (str_is_empty(patch)) {
        pa_finding(SEV_INFO, "Security patch date unavailable",
                   "Cannot compare patch level.");
    } else if (str_compare(patch, min_patch) < 0) {
        pa_finding(SEV_WARN, "Security patch is older than the reference date",
                   "Reported patch " + patch + " is older than " + min_patch + ".");
    } else {
        pa_finding(SEV_OK, "Security patch is up to date",
                   "Reported patch " + patch + " meets the reference date " + min_patch + ".");
    }
}

fn pa_audit_privesc() -> void {
    print_str("\n[5] Privilege escalation indicators\n");

    string debuggable = str_trim(adb_get_prop("ro.debuggable"));
    if (str_equals(debuggable, "1")) {
        pa_finding(SEV_HIGH, "System is debuggable (ro.debuggable=1)",
                   "A debugger can attach to any app; process isolation is weakened.");
    } else if (str_equals(debuggable, "0")) {
        pa_finding(SEV_OK, "System is not debuggable",
                   "Debugging is restricted to debuggable apps only.");
    } else {
        pa_finding(SEV_INFO, "Debuggable flag unavailable",
                   "The device did not report ro.debuggable.");
    }

    string secure = str_trim(adb_get_prop("ro.secure"));
    if (str_equals(secure, "0")) {
        pa_finding(SEV_HIGH, "ro.secure=0",
                   "ADB shell may run with elevated privileges on affected builds.");
    } else if (str_equals(secure, "1")) {
        pa_finding(SEV_OK, "ro.secure=1",
                   "ADB shell is confined to the unprivileged shell UID.");
    } else {
        pa_finding(SEV_INFO, "ro.secure unavailable",
                   "The device did not report ro.secure.");
    }

    string verity = str_trim(adb_get_prop("ro.boot.veritymode"));
    if (str_equals_ignore_case(verity, "enforcing")) {
        pa_finding(SEV_OK, "dm-verity is enforcing",
                   "System partitions are verified at boot time.");
    } else if (str_is_empty(verity)) {
        pa_finding(SEV_INFO, "dm-verity state unavailable",
                   "The device did not report ro.boot.veritymode.");
    } else {
        pa_finding(SEV_HIGH, "dm-verity is not enforcing",
                   "Reported verity mode: " + verity + ". System integrity is weaker.");
    }

    string vbstate = str_trim(adb_get_prop("ro.boot.vbmeta.device_state"));
    if (str_equals_ignore_case(vbstate, "locked")) {
        pa_finding(SEV_OK, "Bootloader is locked",
                   "Verified boot metadata is protected.");
    } else if (str_equals_ignore_case(vbstate, "unlocked")) {
        pa_finding(SEV_HIGH, "Bootloader is unlocked",
                   "An attacker with physical access can replace the boot chain.");
    } else {
        pa_finding(SEV_INFO, "Bootloader state unavailable",
                   "The device did not report ro.boot.vbmeta.device_state.");
    }

    string kernel = pa_shell_trim("uname -r");
    int kmaj = pa_first_int(kernel);
    if (kmaj == 0) {
        pa_finding(SEV_INFO, "Kernel version unavailable",
                   "uname -r did not return a usable version.");
    } else if (kmaj < 5) {
        pa_finding(SEV_WARN, "Old kernel major version",
                   "Kernel " + kernel + " predates many modern exploit mitigations.");
    } else {
        pa_finding(SEV_OK, "Modern kernel major version",
                   "Kernel " + kernel + ". Vendor patches must still be current.");
    }

    if (pa_mount_writable("/system")) {
        pa_finding(SEV_HIGH, "/system is mounted read-write",
                   "A writable system partition allows persistent modification.");
    } else {
        pa_finding(SEV_OK, "/system is mounted read-only",
                   "The system partition is not writable at runtime.");
    }

    string su = pa_shell_trim("which su");
    if (str_is_empty(su) || str_contains(su, "not found")) {
        pa_finding(SEV_OK, "No su binary in PATH",
                   "No root escalation helper is exposed to the shell.");
    } else {
        pa_finding(SEV_WARN, "su binary is present",
                   "Found at " + su + ". Verify this is intentional.");
    }
}

fn pa_usage() -> void {
    print_str("Usage: phone_audit [--min-patch YYYY-MM-DD]\n");
    print_str("Defensive read-only audit of an Android phone connected by USB.\n");
    print_str("Use only on devices you own or are authorized to test.\n");
}

fn main(int argc, char** argv) -> int {
    string min_patch = "2025-01-01";
    int i = 1;
    while (i < argc) {
        string a = cast<string>(argv[i]);
        if (str_equals(a, "--help") || str_equals(a, "-h")) {
            pa_usage();
            return 0;
        }
        if (str_equals(a, "--min-patch") && i + 1 < argc) {
            min_patch = cast<string>(argv[i + 1]);
            i = i + 2;
        } else {
            i = i + 1;
        }
    }

    print_str("==========================================================\n");
    print_str(" Magnetar Phone Audit - USB Android Security & PrivEsc Check \n");
    print_str("==========================================================\n");

    if (adb_available() == false) {
        print_str("[ERROR] adb was not found on this computer.\n");
        return 1;
    }
    pa_line("adb path", adb_path());

    if (adb_device_connected() == false) {
        print_str("[ERROR] No phone detected. Connect it via USB and accept the ADB prompt.\n");
        return 2;
    }
    if (adb_device_authorized() == false) {
        print_str("[ERROR] Phone is not authorized. Unlock it and accept the USB debugging prompt.\n");
        return 3;
    }

    print_str("\nA connected and authorized device was found. Starting read-only checks.\n");
    pa_audit_identity();
    pa_audit_exposure();
    pa_audit_installs();
    pa_audit_platform(min_patch);
    pa_audit_privesc();

    print_str("\n==========================================================\n");
    print_str(" Summary: ");
    print(G_OK); print_str(" OK, ");
    print(G_INFO); print_str(" info, ");
    print(G_WARN); print_str(" warnings, ");
    print(G_HIGH); print_str(" high risk\n");
    print_str("==========================================================\n");
    return 0;
}
