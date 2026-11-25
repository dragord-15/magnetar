// =============================================================================
// units.mg — Unit conversions (SI)
// =============================================================================
// Length, mass, time, temperature, angle, area, volume, speed, energy, power.
// All conversions are float-based (32-bit in Magnetar — limited precision).
// =============================================================================

// -----------------------------------------------------------------------------
// Length (base: meter)
// -----------------------------------------------------------------------------

fn m_to_km(float m) -> float { return m / 1000.0; }
fn km_to_m(float km) -> float { return km * 1000.0; }
fn m_to_cm(float m) -> float { return m * 100.0; }
fn cm_to_m(float cm) -> float { return cm / 100.0; }
fn m_to_mm(float m) -> float { return m * 1000.0; }
fn mm_to_m(float mm) -> float { return mm / 1000.0; }
fn m_to_miles(float m) -> float { return m / 1609.344; }
fn miles_to_m(float mi) -> float { return mi * 1609.344; }
fn m_to_feet(float m) -> float { return m * 3.28084; }
fn feet_to_m(float ft) -> float { return ft / 3.28084; }
fn m_to_inches(float m) -> float { return m * 39.3701; }
fn inches_to_m(float in) -> float { return in / 39.3701; }

// -----------------------------------------------------------------------------
// Mass (base: kilogram)
// -----------------------------------------------------------------------------

fn kg_to_g(float kg) -> float { return kg * 1000.0; }
fn g_to_kg(float g) -> float { return g / 1000.0; }
fn kg_to_mg(float kg) -> float { return kg * 1000000.0; }
fn mg_to_kg(float mg) -> float { return mg / 1000000.0; }
fn kg_to_lb(float kg) -> float { return kg * 2.20462; }
fn lb_to_kg(float lb) -> float { return lb / 2.20462; }
fn kg_to_oz(float kg) -> float { return kg * 35.274; }
fn oz_to_kg(float oz) -> float { return oz / 35.274; }

// -----------------------------------------------------------------------------
// Time (base: second)
// -----------------------------------------------------------------------------

fn s_to_ms(float s) -> float { return s * 1000.0; }
fn ms_to_s(float ms) -> float { return ms / 1000.0; }
fn s_to_min(float s) -> float { return s / 60.0; }
fn min_to_s(float min) -> float { return min * 60.0; }
fn s_to_hours(float s) -> float { return s / 3600.0; }
fn hours_to_s(float h) -> float { return h * 3600.0; }
fn s_to_days(float s) -> float { return s / 86400.0; }
fn days_to_s(float d) -> float { return d * 86400.0; }

// -----------------------------------------------------------------------------
// Temperature
// -----------------------------------------------------------------------------

fn c_to_f(float c) -> float { return c * 9.0 / 5.0 + 32.0; }
fn f_to_c(float f) -> float { return (f - 32.0) * 5.0 / 9.0; }
fn c_to_k(float c) -> float { return c + 273.15; }
fn k_to_c(float k) -> float { return k - 273.15; }
fn f_to_k(float f) -> float { return (f - 32.0) * 5.0 / 9.0 + 273.15; }
fn k_to_f(float k) -> float { return (k - 273.15) * 9.0 / 5.0 + 32.0; }

// -----------------------------------------------------------------------------
// Angle
// -----------------------------------------------------------------------------

const float PI = 3.14159265358979;

fn deg_to_rad(float d) -> float { return d * PI / 180.0; }
fn rad_to_deg(float r) -> float { return r * 180.0 / PI; }

// -----------------------------------------------------------------------------
// Area
// -----------------------------------------------------------------------------

fn m2_to_km2(float m2) -> float { return m2 / 1000000.0; }
fn km2_to_m2(float km2) -> float { return km2 * 1000000.0; }
fn m2_to_cm2(float m2) -> float { return m2 * 10000.0; }
fn cm2_to_m2(float cm2) -> float { return cm2 / 10000.0; }
fn m2_to_hectares(float m2) -> float { return m2 / 10000.0; }
fn hectares_to_m2(float h) -> float { return h * 10000.0; }

// -----------------------------------------------------------------------------
// Volume
// -----------------------------------------------------------------------------

fn m3_to_liters(float m3) -> float { return m3 * 1000.0; }
fn liters_to_m3(float l) -> float { return l / 1000.0; }
fn m3_to_ml(float m3) -> float { return m3 * 1000000.0; }
fn ml_to_m3(float ml) -> float { return ml / 1000000.0; }
fn m3_to_gallons(float m3) -> float { return m3 * 264.172; }
fn gallons_to_m3(float g) -> float { return g / 264.172; }

// -----------------------------------------------------------------------------
// Speed
// -----------------------------------------------------------------------------

fn mps_to_kmph(float mps) -> float { return mps * 3.6; }
fn kmph_to_mps(float kmph) -> float { return kmph / 3.6; }
fn mps_to_mph(float mps) -> float { return mps * 2.23694; }
fn mph_to_mps(float mph) -> float { return mph / 2.23694; }
fn mps_to_knots(float mps) -> float { return mps * 1.94384; }
fn knots_to_mps(float kn) -> float { return kn / 1.94384; }

// -----------------------------------------------------------------------------
// Energy
// -----------------------------------------------------------------------------

fn j_to_kj(float j) -> float { return j / 1000.0; }
fn kj_to_j(float kj) -> float { return kj * 1000.0; }
fn j_to_cal(float j) -> float { return j / 4.184; }
fn cal_to_j(float cal) -> float { return cal * 4.184; }
fn j_to_kcal(float j) -> float { return j / 4184.0; }
fn kcal_to_j(float kcal) -> float { return kcal * 4184.0; }
fn j_to_ev(float j) -> float { return j / 1.602176634e-19; }
fn ev_to_j(float ev) -> float { return ev * 1.602176634e-19; }

// -----------------------------------------------------------------------------
// Power
// -----------------------------------------------------------------------------

fn w_to_kw(float w) -> float { return w / 1000.0; }
fn kw_to_w(float kw) -> float { return kw * 1000.0; }
fn w_to_hp(float w) -> float { return w / 745.7; }
fn hp_to_w(float hp) -> float { return hp * 745.7; }

// -----------------------------------------------------------------------------
// Pressure
// -----------------------------------------------------------------------------

fn pa_to_kpa(float pa) -> float { return pa / 1000.0; }
fn kpa_to_pa(float kpa) -> float { return kpa * 1000.0; }
fn pa_to_bar(float pa) -> float { return pa / 100000.0; }
fn bar_to_pa(float bar) -> float { return bar * 100000.0; }
fn pa_to_atm(float pa) -> float { return pa / 101325.0; }
fn atm_to_pa(float atm) -> float { return atm * 101325.0; }
fn pa_to_psi(float pa) -> float { return pa / 6894.76; }
fn psi_to_pa(float psi) -> float { return psi * 6894.76; }