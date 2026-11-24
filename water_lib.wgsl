/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Water: anime + pixel atlas styles. Optimized for Horizon Android.
// Sparkles gated hard to avoid white grain mid-ocean.

// ---------- anime ----------

const AW_CELL_SPEED: f32 = 0.551524;
const AW_CELL_PERIOD: f32 = 36.0;
const AW_NOISE_PERIOD: f32 = 33.0;
const AW_DRIFT: vec2<f32> = vec2<f32>(0.04, -0.12);
const AW_SMOOTH: f32 = 0.46;
const AW_BAND: f32 = 0.040;
const AW_LINE: f32 = 0.095;
const AW_EDGE_SOFT: f32 = 0.012;
const AW_NOISE_SCALE: f32 = 0.87;
const AW_NOISE_SPEED: f32 = 0.11;
const AW_DISTORT: f32 = 0.26;
const AW_MID: f32 = 0.31;

struct AwVoronoi { edge: f32, to_point: vec2<f32>, cell: vec2<f32> };

fn aw_value_noise(p: vec2<f32>) -> f32 {
    let i0 = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    let a = hash2(fmod2(i0, AW_NOISE_PERIOD)).x;
    let b = hash2(fmod2(i0 + vec2<f32>(1.0, 0.0), AW_NOISE_PERIOD)).x;
    let c = hash2(fmod2(i0 + vec2<f32>(0.0, 1.0), AW_NOISE_PERIOD)).x;
    let d = hash2(fmod2(i0 + vec2<f32>(1.0, 1.0), AW_NOISE_PERIOD)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fn aw_fbm(p: vec2<f32>) -> f32 {
    return 0.5 * aw_value_noise(p) + 0.25 * aw_value_noise(p * 2.0);
}

fn aw_voronoi(p: vec2<f32>, t: f32) -> AwVoronoi {
    let i0 = floor(p);
    let f = fract(p);
    var f1 = 8.0;
    var sf1 = 8.0;
    var out: AwVoronoi;
    out.to_point = vec2<f32>(0.0);
    out.cell = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let n = vec2<f32>(f32(x), f32(y));
            let id = fmod2(i0 + n, AW_CELL_PERIOD);
            let point = 0.5 + 0.5 * sin(t * AW_CELL_SPEED + TAU * hash2(id));
            let off = n + point - f;
            let d = length(off);
            if (d < f1) {
                f1 = d;
                out.to_point = off;
                out.cell = id;
            }
            sf1 = smin(sf1, d, AW_SMOOTH);
        }
    }
    out.edge = f1 - sf1;
    return out;
}

fn aw_ramp(t: f32, day: f32) -> vec3<f32> {
    let deep = mix(vec3<f32>(0.020, 0.075, 0.150), vec3<f32>(0.120, 0.520, 0.740), day);
    let mid  = mix(vec3<f32>(0.040, 0.180, 0.280), vec3<f32>(0.300, 0.690, 0.870), day);
    let high = mix(vec3<f32>(0.300, 0.820, 0.860), vec3<f32>(0.820, 0.940, 0.980), day);
    if (t < AW_MID) {
        return mix(deep, mid, clamp(t / AW_MID, 0.0, 1.0));
    }
    return mix(mid, high, clamp((t - AW_MID) / (1.0 - AW_MID), 0.0, 1.0));
}

fn anime_water_top(
    world_xz: vec2<f32>, time: f32, footprint: f32, flowness: f32,
    fresnel: f32, day: f32, sun_glint: f32
) -> vec4<f32> {
    let scale = 0.42 * water_cell_density;
    let cells_per_px = footprint * scale;
    let detail = 1.0 - smoothstep(0.10, 0.30, cells_per_px);
    var cel = 0.16;
    var v: AwVoronoi;
    v.to_point = vec2<f32>(0.0);
    v.cell = vec2<f32>(0.0);
    let live = detail > 0.0 && flowness < 1.0 && water_cells_still > 0.0;
    if (live) {
        let ct = time * (water_cell_speed * water_motion);
        let p = world_xz * scale;
        let nuv = p * AW_NOISE_SCALE + vec2<f32>(ct * AW_NOISE_SPEED, 0.0);
        let distort = vec2<f32>(aw_fbm(nuv) - 0.375) * AW_DISTORT;
        let uv = p + AW_DRIFT * ct + distort;
        v = aw_voronoi(uv, ct);
        let soft = max(AW_EDGE_SOFT, cells_per_px * 0.7);
        let band = smoothstep(AW_BAND - soft, AW_BAND + soft, v.edge);
        let line = smoothstep(AW_LINE - soft, AW_LINE + soft, v.edge);
        cel = AW_MID * band + (1.0 - AW_MID) * line;
    }
    let still = mix(0.16, cel, detail * water_cells_still);
    let flow_t = mix(0.16, 0.16 + 0.45 * (water_flow_streaks * water_motion), detail);
    let t = mix(still, flow_t, clamp(flowness, 0.0, 1.0));
    var res = vec4<f32>(aw_ramp(t, day), mix(mix(0.32, 0.55, fresnel), 0.85, t));

    // Sparkles only with strong sun glint, rare, never pure white
    let sparkle_cell = hash2(v.cell + 17.0).y;
    if (sun_glint > 0.35 && sparkle_cell > 0.92 && live && detail > 0.5) {
        let a = abs(v.to_point) / 0.16;
        let star = 1.0 - smoothstep(0.0, 1.0, a.x * a.y * 6.0 + (a.x + a.y) * 0.30);
        let twinkle = pow(max(sin(time * 1.900664 + sparkle_cell * 40.0), 0.0), 8.0);
        let sparkle = 0.35 * star * twinkle * sun_glint * detail * (1.0 - flowness);
        let high = mix(vec3<f32>(0.35, 0.75, 0.85), vec3<f32>(0.85, 0.95, 1.0), day);
        res = vec4<f32>(mix(res.rgb, high, clamp(sparkle, 0.0, 0.55)), res.a);
    }
    return res;
}

// ---------- pixel (atlas) ----------

const PIXEL_WATER_FPS: f32 = 6.4;

fn pixel_hash_u(x: i32, y: i32, z: i32) -> u32 {
    let ux = u32(x * 73856093);
    let uy = u32(y * 19349663);
    let uz = u32(z * 83492791);
    var h = ux * 0x8da6b343u ^ uy * 0xd8163841u ^ uz * 0xcb1ab31fu;
    h = h ^ (h >> 16u);
    h = h * 0x7feb352du;
    h = h ^ (h >> 15u);
    h = h * 0x846ca68bu;
    h = h ^ (h >> 16u);
    return h;
}

fn pixel_rand(h: u32) -> f32 {
    return f32(h & 1023u) / 1024.0;
}

fn pixel_shape_at(ax: i32, ay: i32) -> i32 {
    let texel = textureLoad(water_pixel, vec2<i32>(ax, ay), 0);
    if (texel.a < 0.5) { return 0; }
    return i32(texel.r * 3.0 + 0.5);
}

fn pixel_tone(tone: i32, daylight: f32, sunset: f32) -> vec3<f32> {
    // Clamp away pure white sparkle/foam rows for open water
    let t = clamp(tone, 0, 5);
    let night = textureLoad(water_pixel, vec2<i32>(t, 280), 0).rgb;
    let dusk  = textureLoad(water_pixel, vec2<i32>(t, 281), 0).rgb;
    let dayc  = textureLoad(water_pixel, vec2<i32>(t, 282), 0).rgb;
    return mix(mix(night, dayc, daylight), dusk, sunset);
}

fn pixel_sunset(sun_elev: f32) -> f32 {
    return smoothstep(-0.18, -0.02, sun_elev) * (1.0 - smoothstep(0.06, 0.28, sun_elev));
}

fn idiv_pow2(v: i32, bits: i32) -> i32 {
    var d = 1;
    var b = bits;
    if (b < 0) { b = 0; }
    if (b > 5) { b = 5; }
    for (var i = 0; i < b; i = i + 1) { d = d * 2; }
    return v / d;
}

fn pixel_waves(tx: i32, ty: i32, frame: i32, lod: i32) -> i32 {
    let tile_frame = (frame / 4) % 4;
    let tile_x = 128 * (tile_frame % 2);
    let tile_y = 128 * (tile_frame / 2);
    let gx = idiv_pow2(tx, lod);
    let gy = idiv_pow2(ty, lod);
    let sx = tile_x + ((gx + frame / 10) % 128 + 128) % 128;
    let sy = tile_y + ((gy + frame / 15) % 128 + 128) % 128;
    return pixel_shape_at(sx, sy);
}

fn pixel_water_top(
    world_pos: vec3<f32>, time: f32, footprint: f32, flowness: f32,
    fresnel: f32, daylight: f32, sun_elev: f32, glint: f32, rain: f32, tint: vec3<f32>
) -> vec4<f32> {
    let tx = i32(floor(world_pos.x * 16.0));
    let ty = i32(floor(world_pos.z * 16.0));
    let frame = i32(time * PIXEL_WATER_FPS);
    let sunset = pixel_sunset(sun_elev);
    let tpp = max(footprint * 16.0, 0.25);
    let detail = 1.0;
    var alpha = mix(0.55, 0.88, smoothstep(0.30, 0.85, fresnel));

    var shape = 0;
    if (flowness <= 0.5 && detail > 0.05) {
        var lod = 0;
        shape = pixel_waves(tx, ty, frame, lod);
        // Cap shape so we never jump to pure highlight mid-ocean
        shape = min(shape, 2);
    } else if (flowness > 0.5) {
        let flow_h = pixel_rand(pixel_hash_u(tx, i32(world_pos.y * 8.0), frame / 2));
        if (flow_h > 0.60) { shape = 2; }
        else if (flow_h > 0.30) { shape = 1; }
        shape = i32(f32(shape) * (water_flow_streaks * water_motion) + 0.5);
        shape = min(shape, 2);
    }

    // Base tones: mid water, subtle wave lift — never sparkle white
    let near = pixel_tone(2 + min(shape, 2), daylight, sunset * 0.25);
    let far = pixel_tone(4, daylight, sunset);
    let sky_fade = smoothstep(0.40, 0.95, fresnel) * water_cells_still * 0.85;
    var color = mix(near, far, sky_fade) * tint;

    // Rare, soft sun glint only (no random white grain)
    if (glint > 0.40 && detail > 0.4 && flowness < 0.3) {
        let h = pixel_rand(pixel_hash_u(tx, ty, frame / 6));
        if (h > 0.97) {
            let spark = (h - 0.97) / 0.03 * glint * 0.4;
            let high = pixel_tone(5, daylight, sunset);
            color = mix(color, high, clamp(spark, 0.0, 0.45));
        }
    }

    if (shape > 0) {
        alpha = max(alpha, 0.65 + 0.08 * f32(shape));
    }
    return vec4<f32>(color, alpha);
}


// ---------- shore foam (shoreline): where the water column over a block gets thin ----------
// thick: blocks of water along the vertical, from the surface to the block behind it.
// pixel: snap to the 1/16 block grid and make the line a hard pixel step (the "pixel" water style).
fn shore_foam(thick: f32, wp: vec3<f32>, time: f32, day: f32, view_dist: f32, pixel: bool) -> vec4<f32> {
    var q = wp.xz;
    if (pixel) { q = floor(q * 16.0) / 16.0; }
    let waver = 0.70 + 0.30 * sin(dot(q, vec2<f32>(1.7, 2.3)) + time * 1.6)
                           * sin(dot(q, vec2<f32>(-2.9, 1.1)) - time * 1.1);
    let width = 0.16 * water_shore_width * waver;
    var line = 1.0 - smoothstep(width * 0.55, width, thick);
    if (pixel) { line = step(0.5, line); }
    // A second, fainter ripple line a little further out, drifting with time.
    let ring = 1.0 - smoothstep(0.0, 0.05, abs(thick - (0.30 + 0.10 * sin(time * 1.3 + q.x * 2.0 + q.y * 1.5)) * water_shore_width));
    let glow = exp(-thick / 0.50) * 0.28;
    let fade = 1.0 - smoothstep(40.0, 90.0, view_dist);
    let k = max(max(line, ring * 0.55), glow);
    let cool = mix(vec3<f32>(0.20, 0.34, 0.52), vec3<f32>(0.62, 0.88, 0.94), day);
    let white = mix(vec3<f32>(0.55, 0.62, 0.78), vec3<f32>(0.97, 1.00, 1.00), day);
    let col = mix(cool, white, clamp(line + ring * 0.5, 0.0, 1.0));
    return vec4<f32>(col, clamp(k, 0.0, 1.0) * fade);
}
