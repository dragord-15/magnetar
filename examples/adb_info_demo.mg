use "lib/adb.mg";

fn main() {
    print_str("=== Magnetar ADB Controller Test ===\n");
    if (adb_available() == false) {
        print_str("Error: ADB is not found on the system!\n");
        return;
    }

    print_str("ADB Path: ");
    print_str(adb_path());
    print_str("\n");

    print_str("ADB Version: ");
    print_str(adb_version());
    print_str("\n");

    print_str("Connected Devices:\n");
    string devs = adb_devices();
    print_str(devs);
    print_str("\n");

    if (adb_device_connected() == true) {
        print_str("Status: Device detected!\n");
        print_str("Model: ");
        print_str(adb_device_model());
        print_str("\nManufacturer: ");
        print_str(adb_manufacturer());
        print_str("\nAndroid Version: ");
        print_str(adb_android_version());
        print_str("\nBattery Level: ");
        print_str(adb_battery_level());
        print_str("%\n");
    } else {
        print_str("Status: No device connected or unauthorized.\n");
        print_str("Please connect an Android phone via USB with USB Debugging enabled.\n");
    }
}
