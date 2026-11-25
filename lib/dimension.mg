// =============================================================================
// dimension.mg — Dimensional analysis
// =============================================================================
// Represents dimensions as exponents of [M, L, T, I, Theta, N, J]
// (Mass, Length, Time, Current, Temperature, Amount, Luminous intensity)
// =============================================================================

// ⚠️ ملاحظة: هذا التصميم يستخدم fixed<int, 7> — اختبر أن يعمل قبل الاعتماد عليه.

fn dim_new(int m, int l, int t) -> fixed<int, 7> {
    fixed<int, 7> d = {m, l, t, 0, 0, 0, 0};
    return d;
}

fn dim_mul(fixed<int, 7> a, fixed<int, 7> b) -> fixed<int, 7> {
    fixed<int, 7> r = {
        a[0] + b[0], a[1] + b[1], a[2] + b[2],
        a[3] + b[3], a[4] + b[4], a[5] + b[5], a[6] + b[6]
    };
    return r;
}

fn dim_div(fixed<int, 7> a, fixed<int, 7> b) -> fixed<int, 7> {
    fixed<int, 7> r = {
        a[0] - b[0], a[1] - b[1], a[2] - b[2],
        a[3] - b[3], a[4] - b[4], a[5] - b[5], a[6] - b[6]
    };
    return r;
}

fn dim_equal(fixed<int, 7> a, fixed<int, 7> b) -> bool {
    let i = 0;
    while (i < 7) {
        if (a[i] != b[i]) { return false; }
        i = i + 1;
    }
    return true;
}

// دوال مساعدة للأبعاد الشائعة
fn dim_length() -> fixed<int, 7> { return dim_new(0, 1, 0); }
fn dim_mass() -> fixed<int, 7> { return dim_new(1, 0, 0); }
fn dim_time() -> fixed<int, 7> { return dim_new(0, 0, 1); }
fn dim_velocity() -> fixed<int, 7> { return dim_new(0, 1, -1); }
fn dim_acceleration() -> fixed<int, 7> { return dim_new(0, 1, -2); }
fn dim_force() -> fixed<int, 7> { return dim_new(1, 1, -2); }
fn dim_energy() -> fixed<int, 7> { return dim_new(1, 2, -2); }
fn dim_power() -> fixed<int, 7> { return dim_new(1, 2, -3); }
fn dim_pressure() -> fixed<int, 7> { return dim_new(1, -1, -2); }
