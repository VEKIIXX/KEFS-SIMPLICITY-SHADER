/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Shared helpers. Pure math: no stage inputs, so it can be checked on its own.
// Tonemap operators and grade maths implemented for this pack.

const LUMA: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);
const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 { return dot(c, LUMA); }

// Sin-free hash (cheap on mobile GPUs such as Mali).
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn fmod(x: f32, y: f32) -> f32 { return x - y * floor(x / y); }
fn fmod2(x: vec2<f32>, y: f32) -> vec2<f32> { return x - y * floor(x / y); }

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k / 6.0;
}

// ---------- Tonemap operators (input: linear, output: linear 0..1) ----------

fn tm_aces(x_in: vec3<f32>) -> vec3<f32> {
    let x = x_in * 0.6;
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
}

fn tm_jodie(v: vec3<f32>) -> vec3<f32> {
    let l = luma(v);
    let tv = v / (1.0 + v);
    return mix(v / (1.0 + l), tv, tv);
}

fn tm_hejl(hdr: vec3<f32>) -> vec3<f32> {
    let h = hdr * 0.6;
    let va = 1.425 * h + 0.05;
    let vf = (h * va + 0.004) / (h * (va + 0.55) + 0.0491) - 0.0813;
    let w = (3.25 * (1.425 * 3.25 + 0.05) + 0.004) / (3.25 * (3.25 * 1.425 + 0.05 + 0.55) + 0.0491) - 0.0813;
    return vf / w;
}

fn tm_lottes_ch(x: f32) -> f32 {
    let a = 1.6; let d = 0.977; let hdr_max = 8.0; let mid_in = 0.18; let mid_out = 0.267;
    let b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out) /
            ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    let c = (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out) /
            ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    return pow(x, a) / (pow(x, a * d) * b + c);
}
fn tm_lottes(x: vec3<f32>) -> vec3<f32> {
    let p = max(x, vec3<f32>(0.0));
    return vec3<f32>(tm_lottes_ch(p.x), tm_lottes_ch(p.y), tm_lottes_ch(p.z));
}

fn pbr_shoulder(x: f32) -> f32 {
    let start = 0.76;
    let d = 1.0 - start;
    return select(1.0 - d * d / (x + d - start), x, x < start);
}

// PBR Neutral with a per-channel shoulder.
fn tm_pbr_neutral_plus(c_in: vec3<f32>) -> vec3<f32> {
    let start = 0.76;
    let desat = 0.15;
    let x = min(c_in.r, min(c_in.g, c_in.b));
    let offset = select(0.04, x - 6.25 * x * x, x < 0.08);
    var c = c_in - offset;
    let peak = max(c.r, max(c.g, c.b));
    if (peak < start) { return c; }
    let new_peak = pbr_shoulder(peak);
    c = vec3<f32>(pbr_shoulder(c.r), pbr_shoulder(c.g), pbr_shoulder(c.b));
    let g = 1.0 - 1.0 / (desat * (peak - new_peak) + 1.0);
    return mix(c, vec3<f32>(new_peak), g);
}

fn apply_tonemap(c: vec3<f32>) -> vec3<f32> {
    let lin = max(c, vec3<f32>(0.0)) * exposure;
    var out = clamp(lin, vec3<f32>(0.0), vec3<f32>(1.0));
    if (tonemap_op == 1u) { out = tm_aces(lin); }
    else if (tonemap_op == 2u) { out = tm_jodie(lin); }
    else if (tonemap_op == 3u) { out = tm_pbr_neutral_plus(lin); }
    else if (tonemap_op == 4u) { out = tm_hejl(lin); }
    else if (tonemap_op == 5u) { out = tm_lottes(lin); }
    return out;
}

// ---------- Grade (saturation, vibrance, contrast, scene curve and gamma) ----------

fn apply_saturation(c: vec3<f32>, s: f32) -> vec3<f32> { return mix(vec3<f32>(luma(c)), c, s); }

fn apply_vibrance(c: vec3<f32>, k: f32) -> vec3<f32> {
    let mn = min(c.r, min(c.g, c.b));
    let mx = max(c.r, max(c.g, c.b));
    let sat = (1.0 - clamp(mx - mn, 0.0, 1.0)) * clamp(1.0 - mx, 0.0, 1.0) * luma(c) * 5.0;
    let mid = vec3<f32>((mn + mx) * 0.5);
    return mix(c, mix(mid, c, 1.0 + k), sat);
}

fn apply_contrast(c: vec3<f32>, k: f32) -> vec3<f32> { return (c - 0.5) * k + 0.5; }

fn highlight_area(l: f32) -> f32 {
    let t = clamp((l - 0.30) / 0.60, 0.0, 1.0);
    return 0.60 * t * t * t * (1.0 - 0.5 * t) + max(l - 0.90, 0.0);
}

fn scene_grade(c_in: vec3<f32>) -> vec3<f32> {
    var c = c_in;
    // Merged control: scene_light positive lifts highlights, negative deepens shadows.
    let sb = scene_brightness + max(scene_light, 0.0) * 0.5;
    let sd = scene_darkness + max(-scene_light, 0.0) * 0.5;
    if (sb != 0.0) {
        let l = luma(c);
        if (sb > 0.0) {
            let lifted = c + (vec3<f32>(1.0) - c) * (sb * 0.9);
            c = mix(c, lifted, smoothstep(0.30, 0.90, l));
        } else {
            let muted = l + sb * 0.9 * highlight_area(l);
            c = c * (muted / max(l, 1.0e-4));
        }
    }
    if (sd != 0.0) {
        let l = luma(c);
        let lo = 1.0 - smoothstep(0.02, 0.45, l);
        if (sd > 0.0) {
            c = mix(c, c * (1.0 - sd * 0.70), lo);
        } else {
            c = mix(c, c + (vec3<f32>(1.0) - c) * (sd * -0.25), lo);
        }
    }
    return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Purkinje shift: dark colours drift towards a cool scotopic tint.
fn purkinje_effect(c: vec3<f32>, night: f32) -> vec3<f32> {
    let x = 0.5149 * c.r + 0.3244 * c.g + 0.1607 * c.b;
    let y = 0.3654 * c.r + 0.6704 * c.g + 0.0642 * c.b;
    let z = 0.0248 * c.r + 0.1248 * c.g + 0.8504 * c.b;
    let scot = y * (1.33 * (1.0 + (y + z) / (x + 0.0001)) - 1.68);
    let night_col = max(scot, 0.0) * vec3<f32>(0.6, 0.7, 1.1);
    let max_lum = 0.05 + 0.05 * night;
    let blend = 1.0 - smoothstep(0.0, max_lum, scot);
    return mix(c, night_col, purkinje * blend);
}

// ---------- Biome fog ----------
// API 0.1 never names the biome: it gives the biome's climate (temperature, downfall,
// precipitation) and vanilla's fog colour, which the engine already sets per biome. Those pick a
// family here, and the family is blended with the engine's own colour, so a biome this table does
// not name still keeps vanilla's fog. Pure functions: no stage inputs, safe before any stage.

struct BiomeFog {
    color: vec3<f32>,   // the fog's colour for this biome
    density: f32,       // multiplier on the distance density
    height: f32,        // how strongly it pools near the ground, 0..1
};

// Families, in linear-ish display values like the rest of this pack.
const BF_SNOW: vec3<f32> = vec3<f32>(0.74, 0.84, 0.94);
const BF_DESERT: vec3<f32> = vec3<f32>(0.88, 0.75, 0.54);
const BF_SAVANNA: vec3<f32> = vec3<f32>(0.90, 0.78, 0.52);
const BF_JUNGLE: vec3<f32> = vec3<f32>(0.42, 0.63, 0.49);
const BF_SWAMP: vec3<f32> = vec3<f32>(0.46, 0.55, 0.40);
const BF_TAIGA: vec3<f32> = vec3<f32>(0.66, 0.76, 0.84);
const BF_OCEAN: vec3<f32> = vec3<f32>(0.50, 0.70, 0.88);
const BF_MUSHROOM: vec3<f32> = vec3<f32>(0.70, 0.64, 0.78);

fn biome_fog_profile(
    fog_col: vec3<f32>, temperature: f32, downfall: f32, precipitation: u32, wetness: f32
) -> BiomeFog {
    var out: BiomeFog;
    out.color = fog_col;
    out.density = 1.0;
    out.height = 0.30;

    // Climate gates. Vanilla snows below 0.15 and deserts sit at temperature 2.0 with almost no
    // downfall, so these read the same numbers the game uses.
    let snow_k = 1.0 - smoothstep(0.10, 0.26, temperature);
    let hot_k = smoothstep(0.85, 1.15, temperature);
    let dry_k = 1.0 - smoothstep(0.10, 0.30, downfall);
    let wet_k = smoothstep(0.45, 0.85, downfall);
    let cold_k = (1.0 - smoothstep(0.20, 0.55, temperature)) * (1.0 - snow_k);

    // Colour gates on vanilla's fog colour. The engine sets these per biome, so they separate the
    // families the climate alone cannot (swamp, ocean, mushroom fields).
    let green_k = smoothstep(0.02, 0.10, fog_col.g - max(fog_col.r, fog_col.b));
    let dark_blue_k = (1.0 - smoothstep(0.10, 0.30, luma(fog_col))) * smoothstep(0.01, 0.06, fog_col.b - fog_col.r);
    let violet_k = smoothstep(0.01, 0.06, fog_col.b - fog_col.g) * smoothstep(-0.02, 0.05, fog_col.r - fog_col.g);

    let desert_k = hot_k * dry_k;
    let savanna_k = hot_k * (1.0 - dry_k) * (1.0 - wet_k);
    let jungle_k = wet_k * smoothstep(0.45, 0.90, temperature);
    let taiga_k = cold_k * wet_k;

    // Deserts: thin but wide, warm sand; the haze takes the sky's place.
    out.color = mix(out.color, BF_DESERT, 0.75 * desert_k);
    out.density = mix(out.density, 0.80, desert_k);
    out.height = mix(out.height, 0.12, desert_k);
    // Savannas: golden, a little thicker.
    out.color = mix(out.color, BF_SAVANNA, 0.55 * savanna_k);
    out.density = mix(out.density, 0.92, savanna_k);
    // Jungles: humid green-teal, thick and low.
    out.color = mix(out.color, BF_JUNGLE, 0.60 * jungle_k);
    out.density = mix(out.density, 1.30, jungle_k);
    out.height = mix(out.height, 0.55, jungle_k);
    // Swamps: murky green, the thickest of the overworld.
    out.color = mix(out.color, BF_SWAMP, 0.70 * green_k);
    out.density = mix(out.density, 1.35, green_k);
    out.height = mix(out.height, 0.85, green_k);
    // Snow: pale and cold, denser, mid-height.
    out.color = mix(out.color, BF_SNOW, 0.65 * snow_k);
    out.density = mix(out.density, 1.25, snow_k);
    out.height = mix(out.height, 0.45, snow_k);
    // Taiga: cool blue-grey.
    out.color = mix(out.color, BF_TAIGA, 0.45 * taiga_k);
    out.density = mix(out.density, 1.10, taiga_k);
    // Ocean and deep dark: a low blue fog.
    out.color = mix(out.color, BF_OCEAN, 0.40 * dark_blue_k);
    out.density = mix(out.density, 1.05, dark_blue_k);
    out.height = mix(out.height, 0.20, dark_blue_k);
    // Mushroom fields: dusty lilac-grey.
    out.color = mix(out.color, BF_MUSHROOM, 0.45 * violet_k);
    // Snow falling makes the fog whiter; rain thickens it. Wetness keeps the last of it after the
    // storm has passed instead of cutting the fog off in one frame.
    let snowy = select(0.0, 1.0, precipitation == 2u);
    out.color = mix(out.color, BF_SNOW, snowy * 0.25 * smoothstep(0.05, 0.60, wetness));
    out.density = out.density * (1.0 + 0.55 * wetness);

    return out;
}

fn final_grade(c_in: vec3<f32>) -> vec3<f32> {
    var c = scene_grade(c_in);
    c = apply_vibrance(c, vibrance);
    c = apply_saturation(c, saturation);
    c = apply_contrast(c, contrast);
    // Split tone: cool teal-blue shadows, warm highlights.
    let sl = luma(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)));
    c = mix(c, c * vec3<f32>(0.88, 0.98, 1.12), (1.0 - smoothstep(0.0, 0.5, sl)) * split_tone);
    c = mix(c, c * vec3<f32>(1.06, 1.00, 0.92), smoothstep(0.55, 1.0, sl) * split_tone);
    c = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
    return pow(c, vec3<f32>(1.0 / gamma_adjust));
}
