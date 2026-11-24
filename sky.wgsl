/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Sky stage. Glue around sky_lib.wgsl. SkyInput: direction (unit view ray), color (vanilla's sky).

fn hash3_sky(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// End: a purple sky with a swirling galaxy overhead, a bright core, stars and a purple band at the horizon.
fn end_sky(ray: vec3<f32>, t: f32) -> vec3<f32> {
    let base = mix(vec3<f32>(0.22, 0.09, 0.40), vec3<f32>(0.08, 0.03, 0.20), smoothstep(-0.2, 0.8, ray.y));
    let axis = normalize(vec3<f32>(0.0, 1.0, 0.25));
    let r = 1.0 - clamp(dot(ray, axis), 0.0, 1.0);
    let angle = atan2(ray.z, ray.x);
    let arms = 0.5 + 0.5 * sin(angle * 2.0 + log(r + 0.02) * 5.0 - t * 0.12);
    let band = smoothstep(0.35, 0.90, arms) * exp(-r * 2.0);
    let core = exp(-r * 10.0);
    var g = base + vec3<f32>(0.62, 0.32, 1.00) * band * 1.1 + vec3<f32>(1.00, 0.92, 1.00) * core * 1.6;
    let cell = floor(ray * 240.0);
    let h = hash3_sky(cell);
    let star = step(0.994, h) * (0.6 + 0.4 * sin(t * 1.5 + h * 40.0));
    g += vec3<f32>(1.0) * star * 0.9;
    let ribbon = exp(-abs(ray.y - 0.10) * 10.0);
    g += vec3<f32>(0.75, 0.50, 1.00) * ribbon * 0.7;
    return g;
}

// Nether: a red-orange sky that glows brighter towards the horizon, with a slow flicker.
fn nether_sky(ray: vec3<f32>, t: f32) -> vec3<f32> {
    let hz = exp(-max(ray.y, 0.0) * 3.0);
    let g = mix(vec3<f32>(0.55, 0.10, 0.03), vec3<f32>(0.95, 0.35, 0.10), hz);
    return g * (0.9 + 0.1 * sin(t * 1.3 + ray.x * 6.0 + ray.z * 5.0));
}

fn sky(input: SkyInput) -> vec4<f32> {
    let ray = normalize(input.direction);
    var col = sky_gradient(ray, frame.sun_direction, frame.sky_color, frame.fog_color, frame.rain);
    // A little of vanilla's fog colour at the horizon, so the sky meets the distance fog.
    col = mix(col, frame.fog_color, 0.10 * (1.0 - smoothstep(0.0, 0.25, ray.y)));
    // Vanilla's own colour carries the sunrise/sunset glow; keep a share of it.
    col = mix(col, input.color.rgb, 0.15);

    // Per-biome horizon: the sky takes the same fog colour as the distance fog, so a snowy valley,
    // a desert or a swamp reads as one place instead of a gradient over a differently coloured haze.
    let bio = biome_fog_profile(frame.fog_color, frame.temperature, frame.downfall, frame.precipitation, frame.wetness);
    let band = 1.0 - smoothstep(0.0, 0.22, ray.y);
    col = mix(col, bio.color, band * 0.22 * clamp((biome_mood * biome_fog), 0.0, 2.0));

    // Dimension from the frame: -1 the Nether, 1 the End.
    let nk = select(0.0, 1.0, frame.dimension == -1);
    let ek = select(0.0, 1.0, frame.dimension == 1);
    col = mix(col, nether_sky(ray, frame.time), nk);
    col = mix(col, end_sky(ray, frame.time), ek);

    return vec4<f32>(col, 1.0);
}
