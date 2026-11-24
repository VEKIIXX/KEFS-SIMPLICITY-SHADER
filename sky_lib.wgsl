/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Sky: day/dusk/night gradient, corona, vivid sunset. Pure functions of directions and colours.

fn sky_lift(h: f32) -> f32 { let low = 1.0 - clamp(h, 0.0, 1.0); return 1.0 - low * low; }

fn sunset_side(ray: vec3<f32>, sun: vec3<f32>) -> f32 {
    let lr = length(ray.xz);
    let ls = length(sun.xz);
    if (lr < 1.0e-4 || ls < 1.0e-4) { return 0.5; }
    return dot(ray.xz / lr, sun.xz / ls) * 0.5 + 0.5;
}

fn sunset_amount(elev: f32, sky_col: vec3<f32>, rain: f32) -> f32 {
    let hi = max(sky_col.r, max(sky_col.g, sky_col.b));
    let lo = min(sky_col.r, min(sky_col.g, sky_col.b));
    let clear = smoothstep(0.12, 0.35, (hi - lo) / max(hi, 1.0e-3));
    return vivid_sunset * clear * smoothstep(-0.20, -0.02, elev) * (1.0 - smoothstep(0.10, 0.32, elev)) * (1.0 - rain);
}

fn sunset_sky(ray: vec3<f32>, sun: vec3<f32>, elev: f32, h_in: f32) -> vec3<f32> {
    let side = sunset_side(ray, sun);
    let ss = side * side;
    let h = clamp(h_in, 0.0, 1.0);
    let horizon = mix(vec3<f32>(0.66, 0.46, 0.60), vec3<f32>(1.00, 0.66, 0.26), ss);
    let band = mix(vec3<f32>(0.58, 0.40, 0.62), vec3<f32>(1.00, 0.40, 0.16), ss);
    let high = mix(vec3<f32>(0.36, 0.30, 0.58), vec3<f32>(0.90, 0.36, 0.44), ss * side);
    let zenith = vec3<f32>(0.20, 0.23, 0.50);
    var c = mix(horizon, band, smoothstep(0.0, 0.30, h));
    c = mix(c, high, smoothstep(0.15, 0.55, h));
    c = mix(c, zenith, smoothstep(0.40, 0.90, h));
    let ts = max(dot(ray, sun), 0.0);
    c += vec3<f32>(1.00, 0.74, 0.38) * (0.55 * pow(ts, 10.0) + 0.25 * pow(ts, 3.0) * (1.0 - smoothstep(0.0, 0.3, ray.y)));
    return c * mix(0.40, 1.0, smoothstep(-0.16, 0.02, elev));
}

// ray: unit view direction, sun: unit direction to the sun, sky_col/fog_col: vanilla's colours.
fn sky_gradient(ray: vec3<f32>, sun: vec3<f32>, sky_col: vec3<f32>, fog_col: vec3<f32>, rain: f32) -> vec3<f32> {
    let elev = sun.y;
    let day = smoothstep(-0.18, 0.16, elev);
    let dusk = (1.0 - smoothstep(0.04, 0.34, abs(elev))) * day;

    let day_zenith = mix(vec3<f32>(0.24, 0.44, 0.88), sky_col, 0.45);
    let day_horizon = mix(fog_col, sky_col, 0.18) * vec3<f32>(0.94, 1.0, 1.0);
    let night_zenith = vec3<f32>(0.008, 0.014, 0.048);
    let night_horizon = mix(fog_col * vec3<f32>(0.22, 0.28, 0.42), vec3<f32>(0.035, 0.048, 0.090), 0.70);

    let zenith = mix(night_zenith, day_zenith, day);
    var horizon = mix(night_horizon, day_horizon, day);
    horizon = mix(horizon, vec3<f32>(0.97, 0.58, 0.38), dusk * 0.55);

    var g = mix(horizon, zenith, sky_lift(ray.y));

    let ts = max(dot(ray, sun), 0.0);
    let vis = smoothstep(-0.10, 0.06, elev);
    let corona = pow(ts, 28.0) * vis;
    let veil = pow(ts, 10.0) * vis * (1.0 - smoothstep(0.08, 0.42, elev));
    g = mix(g, vec3<f32>(1.00, 0.80, 0.55), corona * 0.22);
    g = mix(g, vec3<f32>(1.00, 0.64, 0.42), veil * 0.18);
    g += vec3<f32>(1.00, 0.82, 0.62) * (0.20 * pow(ts, 5.0) * vis * smoothstep(-0.10, 0.10, elev) * (1.0 - sky_lift(ray.y)));

    let sset = sunset_amount(elev, sky_col, rain);
    if (sset > 0.0) { g = mix(g, sunset_sky(ray, sun, elev, ray.y), sset); }

    if (night_sky) {
        let moon = -sun;
        let m_vis = smoothstep(-0.05, 0.12, moon.y) * (1.0 - day) * (1.0 - rain);
        let tm = max(dot(ray, moon), 0.0);
        g += vec3<f32>(0.62, 0.72, 0.95) * ((pow(tm, 18.0) * 0.55 + pow(tm, 4.0) * 0.06) * m_vis);
        g += vec3<f32>(0.18, 0.24, 0.40) * (pow(1.0 - clamp(ray.y, 0.0, 1.0), 3.0) * 0.30 * m_vis);
    }
    return g;
}

// Flat "story" cloud colour: bottom/top ramp, tinted by sunset and rain (analytic).
fn cloud_color(ray: vec3<f32>, sun: vec3<f32>, height01: f32, rain: f32) -> vec3<f32> {
    let day = smoothstep(-0.18, 0.16, sun.y);
    let bottom = mix(vec3<f32>(0.10, 0.12, 0.22), vec3<f32>(0.80, 0.86, 0.96), day);
    let top = mix(vec3<f32>(0.18, 0.20, 0.34), vec3<f32>(1.00, 1.00, 1.00), day);
    var c = mix(bottom, top, height01);
    let sset = (1.0 - smoothstep(0.10, 0.32, sun.y)) * smoothstep(-0.20, -0.02, sun.y) * vivid_sunset * 4.0;
    let side = sunset_side(ray, sun);
    let warm = mix(vec3<f32>(0.38, 0.31, 0.54), vec3<f32>(1.00, 0.52, 0.20), smoothstep(0.10, 0.95, side));
    c = mix(c, warm, clamp(sset, 0.0, 1.0));
    return mix(c, vec3<f32>(0.40, 0.43, 0.48), rain * 0.60);
}
