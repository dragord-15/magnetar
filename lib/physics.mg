// =============================================================================
// physics.mg — Physical constants and equations
// =============================================================================

use "units";
use"lib/math.mg";
// -----------------------------------------------------------------------------
// Constants (SI)
// -----------------------------------------------------------------------------

const float C_LIGHT      = 299792458.0;          // m/s
const float G_GRAVITY    = 6.67430e-11;           // m^3/(kg*s^2)
const float PLANCK_H     = 6.62607015e-34;        // J*s
const float BOLTZMANN_K  = 1.380649e-23;          // J/K
const float AVOGADRO_NA  = 6.02214076e23;         // 1/mol
const float ELECTRON_M   = 9.1093837015e-31;      // kg
const float PROTON_M     = 1.67262192369e-27;     // kg
const float GAS_R        = 8.314462618;           // J/(mol*K)
const float EARTH_G      = 9.80665;               // m/s^2
const float ATOMIC_U     = 1.66053906660e-27;     // kg

// -----------------------------------------------------------------------------
// Kinematics
// -----------------------------------------------------------------------------

// v = v0 + a*t
fn velocity(float v0, float a, float t) -> float {
    return v0 + a * t;
}

// x = x0 + v0*t + 0.5*a*t^2
fn position(float x0, float v0, float a, float t) -> float {
    return x0 + v0 * t + 0.5 * a * t * t;
}

// v^2 = v0^2 + 2*a*dx
fn velocity_squared(float v0, float a, float dx) -> float {
    return v0 * v0 + 2.0 * a * dx;
}

// t = (v - v0) / a
fn time_to_velocity(float v0, float v, float a) -> float {
    return (v - v0) / a;
}

// -----------------------------------------------------------------------------
// Dynamics
// -----------------------------------------------------------------------------

// F = m*a
fn force(float mass, float accel) -> float {
    return mass * accel;
}

// a = F/m
fn acceleration(float force, float mass) -> float {
    return force / mass;
}

// W = F*d*cos(theta)
fn work(float force, float distance, float theta) -> float {
    return force * distance * cos(theta);
}

// P = W/t
fn power(float work, float time) -> float {
    return work / time;
}

// KE = 0.5*m*v^2
fn kinetic_energy(float mass, float velocity) -> float {
    return 0.5 * mass * velocity * velocity;
}

// PE = m*g*h
fn potential_energy(float mass, float height) -> float {
    return mass * EARTH_G * height;
}

// p = m*v
fn momentum(float mass, float velocity) -> float {
    return mass * velocity;
}

// -----------------------------------------------------------------------------
// Circular motion
// -----------------------------------------------------------------------------

// a = v^2/r
fn centripetal_accel(float v, float r) -> float {
    return v * v / r;
}

// F = m*v^2/r
fn centripetal_force(float mass, float v, float r) -> float {
    return mass * v * v / r;
}

// T = 2*pi*r/v
fn orbital_period(float r, float v) -> float {
    return 2.0 * PI * r / v;
}

// -----------------------------------------------------------------------------
// Gravity
// -----------------------------------------------------------------------------

// F = G*m1*m2/r^2
fn gravitational_force(float m1, float m2, float r) -> float {
    return G_GRAVITY * m1 * m2 / (r * r);
}

// v_escape = sqrt(2*G*M/r)
fn escape_velocity(float mass, float r) -> float {
    return sqrt(2.0 * G_GRAVITY * mass / r);
}

// -----------------------------------------------------------------------------
// Waves and sound
// -----------------------------------------------------------------------------

// v = f * lambda
fn wave_speed(float freq, float wavelength) -> float {
    return freq * wavelength;
}

fn frequency_from_wavelength(float speed, float wavelength) -> float {
    return speed / wavelength;
}

fn wavelength_from_frequency(float speed, float freq) -> float {
    return speed / freq;
}

// -----------------------------------------------------------------------------
// Thermodynamics
// -----------------------------------------------------------------------------

// Q = m*c*dT
fn heat_energy(float mass, float specific_heat, float delta_t) -> float {
    return mass * specific_heat * delta_t;
}

// E = k*T (average kinetic energy of a particle)
fn thermal_energy(float temperature_k) -> float {
    return BOLTZMANN_K * temperature_k;
}

// -----------------------------------------------------------------------------
// Electricity
// -----------------------------------------------------------------------------

// V = I*R
fn voltage(float current, float resistance) -> float {
    return current * resistance;
}

// P = V*I
fn electrical_power(float voltage, float current) -> float {
    return voltage * current;
}

// E = P*t
fn electrical_energy(float power, float time) -> float {
    return power * time;
}

// -----------------------------------------------------------------------------
// Optics
// -----------------------------------------------------------------------------

// n = c/v
fn refractive_index(float v) -> float {
    return C_LIGHT / v;
}

// E = h*f
fn photon_energy(float frequency) -> float {
    return PLANCK_H * frequency;
}

// lambda = h/(m*v)
fn de_broglie_wavelength(float mass, float velocity) -> float {
    return PLANCK_H / (mass * velocity);
}

// -----------------------------------------------------------------------------
// Relativity
// -----------------------------------------------------------------------------

// gamma = 1 / sqrt(1 - v^2/c^2)
fn lorentz_factor(float v) -> float {
    let ratio = v / C_LIGHT;
    return 1.0 / sqrt(1.0 - ratio * ratio);
}

// E = m*c^2
fn mass_energy(float mass) -> float {
    return mass * C_LIGHT * C_LIGHT;
}

// E^2 = (p*c)^2 + (m*c^2)^2
fn relativistic_energy(float mass, float momentum) -> float {
    let pc = momentum * C_LIGHT;
    let mc2 = mass * C_LIGHT * C_LIGHT;
    return sqrt(pc * pc + mc2 * mc2);
}

// -----------------------------------------------------------------------------
// Fluids
// -----------------------------------------------------------------------------

// P = F/A
fn pressure(float force, float area) -> float {
    return force / area;
}

// rho = m/V
fn density(float mass, float volume) -> float {
    return mass / volume;
}

// P + 0.5*rho*v^2 + rho*g*h = const (Bernoulli)
fn bernoulli_pressure(float rho, float v, float h) -> float {
    return 0.5 * rho * v * v + rho * EARTH_G * h;
}
