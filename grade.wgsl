/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Last pass: atmosphere, bloom, tonemap and grade, all in one full-screen pass
// (one pass instead of three = much less memory traffic on integrated and mobile GPUs).

fn value_noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    let a = hash2(i).x;
    let b = hash2(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash2(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash2(i + vec2<f32>(1.0, 1.0)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fn bloom_tap(uv: vec2<f32>) -> vec4<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let b = c * smoothstep(0.55, 1.10, luma(c));
    return vec4<f32>(b, 1.0 / (1.0 + luma(b)));
}

// Screen position of the sun: climb the gradient of dot(view direction, sun direction) over uv.
// No projection matrix is needed, because view_position gives the direction for any uv.
fn sun_uv_screen() -> vec2<f32> {
    let sun_w = frame.sun_direction;
    var uv = vec2<f32>(0.5, 0.5);
    var sz = 0.25;
    for (var i = 0; i < 3; i = i + 1) {
        let hh = 0.01;
        let gx = dot(normalize(view_position(uv + vec2<f32>(hh, 0.0), 0.5)), sun_w)
               - dot(normalize(view_position(uv - vec2<f32>(hh, 0.0), 0.5)), sun_w);
        let gy = dot(normalize(view_position(uv + vec2<f32>(0.0, hh), 0.5)), sun_w)
               - dot(normalize(view_position(uv - vec2<f32>(0.0, hh), 0.5)), sun_w);
        let gv = vec2<f32>(gx, gy);
        // Clamped: a corner pixel can push the walk out of the frame, and a NaN here would smear
        // the shafts over the whole screen.
        if (length(gv) > 1.0e-6) { uv = clamp(uv + normalize(gv) * sz, vec2<f32>(0.0), vec2<f32>(1.0)); }
        sz = sz * 0.5;
    }
    return uv;
}

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb;
    let d = input.depth;
    // Camera-relative position of this pixel, computed once and reused by every block below.
    let vpos_d = view_position(input.uv, d);
    // Dimensions come from the frame, never from the fog colour: a red fog at sunset or a purple
    // one in a swamp is weather, not another world. Defined early: the ambient gate below needs them.
    let is_nether = frame.dimension == -1;
    let is_end = frame.dimension == 1;
    let nether = nether_fog * select(0.0, 1.0, is_nether);
    // Far anchor for world-locked ambient effects: computed once, shared by all of them.
    // (Only when at least one such effect is on; the branch is uniform per frame.)
    var vpos_far = vec3<f32>(0.0, 0.0, -8.0);
    let any_ambient = (leaf_fall * air_particles) + (air_smoke * air_particles) + bubbles + (runes * dark_glow) + end_motes + (fireflies * night_glow)
                    + (sparks * air_particles) + (drips * air_particles) + (soul_wisps * dark_glow) + sun_dust + (spores * nether_fx) + (moon_motes * night_glow)
                    + sparkles + (sculk_pulse * dark_glow) + (crystal_glow * dark_glow) + nether;
    if (any_ambient > 0.0) {
        vpos_far = view_position(input.uv, select(8.0, d, d > 0.0));
    }

    // Ambient occlusion (End only): darken pixels in a crevice, using the depth of 8 neighbours around this pixel.
    // Reversed depth: a neighbour nearer to the camera has a larger value, so it occludes this pixel.
    if (frame.dimension == 1 && d > 0.0 && ao_strength > 0.0) {
        var occ = 0.0;
        let rpx = vec2<f32>(6.0, 6.0) / frame.resolution;
        for (var i = 0; i < 6; i = i + 1) {
            let ang = f32(i) * 1.0471976;
            let off = vec2<f32>(cos(ang), sin(ang)) * rpx;
            let dn = depth_at(input.uv + off);
            let diff = dn - d;
            occ += smoothstep(0.0005, 0.01, diff) * (1.0 - smoothstep(0.01, 0.04, diff));
        }
        c *= 1.0 - clamp(occ / 6.0 * ao_strength, 0.0, 0.8);
    }
    let time = frame.time;
    let elev = frame.sun_direction.y;
    let day = smoothstep(-0.18, 0.16, elev);
    let sunset = (1.0 - smoothstep(0.06, 0.30, elev)) * smoothstep(-0.18, -0.02, elev);

    // View direction (world) and the sun's alignment, used by haze, glow and scattering.
    let sun_vis = smoothstep(-0.10, 0.10, elev);
    let moon_vis = smoothstep(-0.05, 0.15, frame.moon_direction.y) * (1.0 - day);
    var dir = vec3<f32>(0.0, 1.0, 0.0);
    var sd = -1.0;
    let glow_col = mix(vec3<f32>(1.0, 0.86, 0.62), vec3<f32>(1.0, 0.55, 0.28), sunset);
    if (atmo_haze > 0.0 || sun_glow > 0.0 || godrays > 0.0) {
        dir = normalize(view_position(input.uv, 0.5));
        sd = dot(dir, frame.sun_direction);
    }

    // Distance fog. Colour and thickness follow the biome: common.wgsl classifies it from the
    // climate and vanilla's per-biome fog colour, because API 0.1 exposes no biome id.
    let biome = biome_fog_profile(frame.fog_color, frame.temperature, frame.downfall, frame.precipitation, frame.wetness);
    // Underwater the water block below owns the colour, so the biome tint steps back there.
    let mood = clamp((biome_mood * biome_fog), 0.0, 2.0) * select(1.0, 0.35, frame.eye_in == 1u);
    // Forward scattering: the fog turns lighter and warmer towards the sun, golden at sunset,
    // blue-violet at night and in rain.
    if (atmo_haze > 0.0 && d > 0.0 && !is_nether) {
        let dist = length(vpos_d);
        var haze_col = mix(frame.fog_color, biome.color, clamp(0.85 * mood, 0.0, 1.0));
        haze_col = mix(haze_col, vec3<f32>(1.0, 0.62, 0.34), sunset * 0.55);
        haze_col = mix(vec3<f32>(0.10, 0.16, 0.36), haze_col, day);
        let toward = pow(max(sd, 0.0), 6.0) * sun_vis * (1.0 - frame.rain);
        haze_col = haze_col + glow_col * toward * 0.35;
        if (is_end) { haze_col = mix(haze_col, vec3<f32>(0.62, 0.46, 0.92), 0.6); }

        // Fogulous-style shaping: fog thickens at night and in rain, and its start distance grows
        // with the render distance so the view never turns into a wall up close. The sun below the
        // horizon is the night signal (no biome id needed).
        let night_k = clamp(1.0 - smoothstep(-0.15, 0.10, frame.sun_direction.y), 0.0, 1.0);
        let rd_chunks = frame.render_distance / 16.0;
        let fog_start = 12.0 * max(1.0, 1.0 + (rd_chunks - 1.0) * 0.75);
        let dist_eff = max(dist - fog_start, 0.0);

        // Thickness: the biome scales it, and the density option lets one slider thin or thicken
        // every biome at once without losing the differences between them. Weather (night + rain)
        // thickens it further, Fogulous-style, scaled by atmo_haze.
        let base_dens = (0.008 + 0.010 * frame.rain + 0.006 * sunset) * atmo_haze;
        let weather_boost = 1.0 + (0.5 * night_k + 0.4 * frame.rain) * atmo_haze * 0.6;
        let dens = base_dens * mix(1.0, biome.density, clamp(mood, 0.0, 1.0)) * clamp((biome_fog_density * biome_fog), 0.0, 2.5) * weather_boost;
        c = mix(c, haze_col, clamp(1.0 - exp(-dist_eff * dens), 0.0, 0.65));

        // Ground fog: the same colour pooled low, so valleys and hollows read as mist and the
        // horizon is not a flat wall. It fades with distance and stops underwater. Thicker at night.
        let world_y = vpos_d.y + frame.camera_position.y;
        let pooling = exp(-max(world_y - 62.0, 0.0) * 0.085) * mix(0.4, 1.0, biome.height);
        let near = 1.0 - clamp(dist / max(frame.render_distance, 16.0), 0.0, 1.0);
        let low = clamp(ground_fog, 0.0, 1.5) * pooling * near * select(1.0, 0.35, frame.eye_in == 1u) * (1.0 + 0.3 * night_k);
        c = mix(c, haze_col, clamp(low, 0.0, 0.55));
    }

    // Horizon warmth (Realistic Biomes style): by day the sky near the horizon and distant terrain take a soft
    // golden tint, so the far view looks hazy and warm. Small on purpose; strength is the Horizon warmth option.
    if ((warm_horizon * desert_atmo) > 0.0 && day > 0.0) {
        let warm_c = vec3<f32>(1.00, 0.84, 0.62);
        if (d <= 0.0) {
            let hk = (1.0 - smoothstep(0.0, 0.30, dir.y)) * day * (warm_horizon * desert_atmo);
            c = mix(c, warm_c, 0.22 * hk);
        } else {
            let dn = min(length(vpos_d) / 120.0, 1.0);
            c = mix(c, warm_c, 0.10 * day * (warm_horizon * desert_atmo) * dn);
        }
    }

    // Aurora (night sky only, no rain): soft moving curtains in the upper sky, from two noise layers
    // drifting slowly. Projected from the view direction, so there is no seam at the horizon.
    if (aurora > 0.0 && d <= 0.0 && frame.rain < 0.5 && (1.0 - day) > 0.3) {
        let adir = normalize(view_position(input.uv, 0.5));
        let aalt = adir.y;
        if (aalt > 0.12) {
            let aq = adir.xz / max(aalt, 0.15);
            let atime = frame.time * 0.03;
            let an1 = value_noise2(aq * 1.6 + vec2<f32>(atime, 0.0));
            let an2 = value_noise2(aq * 4.3 - vec2<f32>(atime * 1.6, 2.1) + vec2<f32>(0.0, aalt * 3.0));
            let curtain = smoothstep(0.45, 0.85, an1 * 0.6 + an2 * 0.4);
            let aband = smoothstep(0.12, 0.35, aalt) * (1.0 - smoothstep(0.55, 0.90, aalt));
            let acol = mix(vec3<f32>(0.20, 1.00, 0.55), vec3<f32>(0.55, 0.35, 1.00), value_noise2(aq * 0.8 + vec2<f32>(atime * 0.5)));
            c = c + acol * curtain * aband * aurora * (1.0 - day) * 0.35;
        }
    }

    // Meteor shower (night sky only, no rain): a short streak along a random arc of the sky, once per period.
    // The arc is a great circle through two random sky points; the streak is drawn only in the sky (d <= 0).
    if (meteor_shower > 0.0 && d <= 0.0 && frame.rain < 0.3 && (1.0 - day) > 0.5) {
        let period = 24.0;
        let mph = fract(frame.time / period);
        if (mph < 0.12) {
            let midx = floor(frame.time / period);
            let mh = hash2(vec2<f32>(midx, 7.0));
            let mh2 = hash2(vec2<f32>(midx, 13.0));
            let mp0 = normalize(vec3<f32>(mh.x * 2.0 - 1.0, 0.25 + 0.6 * mh.y, mh2.x * 2.0 - 1.0));
            let mp1 = normalize(mp0 + vec3<f32>(mh2.y - 0.5, -0.4, mh.x - 0.5) * 0.9);
            let maxis = normalize(cross(mp0, mp1));
            let mv = normalize(view_position(input.uv, 0.5));
            let span = 0.7;
            let mtheta = atan2(dot(mv, mp1), dot(mv, mp0));
            let mhead = (mph / 0.12) * span;
            let mtail = mhead - 0.22;
            let mband = smoothstep(mtail, mhead, mtheta) * (1.0 - smoothstep(mhead, mhead + 0.01, mtheta));
            let mthin = 1.0 - smoothstep(0.0, 0.012, abs(dot(mv, maxis)));
            let mstreak = mband * mthin * meteor_shower;
            c = c + vec3<f32>(1.0, 0.95, 0.80) * mstreak * 1.2;
        }
    }

    // Desert dust: by day in warm fog, dust patches drift over the distance (own implementation).
    if ((dust_storm * desert_atmo) > 0.0 && day > 0.0 && d > 0.0 && length(vpos_d) < calc_radius) {
        let vpd = vpos_d;
        let dn = min(length(vpd) / 100.0, 1.0);
        let wxz = vpd.xz + frame.camera_position.xz;
        let warm_d = smoothstep(0.02, 0.25, frame.fog_color.r - frame.fog_color.b);
        let dust_patch = value_noise2(wxz * 0.02 + vec2<f32>(time * 0.03, time * 0.01));
        let dust_k = warm_d * day * (dust_storm * desert_atmo) * dn * smoothstep(0.45, 0.80, dust_patch) * 0.5;
        c = mix(c, vec3<f32>(0.92, 0.76, 0.50), dust_k);
    }

    // Nether haze: a thick warm red-orange fog that thickens with distance, with a glow from the lava.
    if (nether > 0.0) {
        let fog_n = mix(frame.fog_color, vec3<f32>(1.0, 0.36, 0.12), 0.45) * (1.0 + 0.25 * nether);
        if (d > 0.0) {
            let dist_n = length(vpos_d);
            let amt = clamp(1.0 - exp(-dist_n * 0.030 * nether), 0.0, 0.85);
            c = mix(c, fog_n, amt);
        } else {
            c = mix(c, fog_n, 0.55 * nether);
        }
    }

    // Sun and moon glow, and a smooth scattering halo in the sky (no streaks, no pattern):
    // a wide soft falloff plus a tighter bright core, like light scattered by the air.
    if ((sun_glow > 0.0 || godrays > 0.0) && (sun_vis > 0.0 || moon_vis > 0.0)) {
        let sky_k = select(0.0, 1.0, d <= 0.0);   // sky only: no glow or halo drawn over terrain
        if (sun_vis > 0.0 && sd > 0.0) {
            let theta = sqrt(max(2.0 * (1.0 - sd), 0.0));
            let wide = exp(-theta * 2.2) * 0.30 + exp(-theta * 7.0) * 0.30;
            let core = pow(max(sd, 0.0), 60.0) * 0.30;
            let scatter = (wide * godrays + core * sun_glow) * sun_vis * (1.0 - frame.rain * 0.8);
            c += glow_col * scatter * sky_k * 0.6;
        }
        if (sun_glow > 0.0 && moon_vis > 0.0) {
            let md = dot(dir, frame.moon_direction);
            if (md > 0.3) {
                let m = max(md, 0.0);
                c += vec3<f32>(0.45, 0.58, 1.0) * (pow(m, 10.0) * 0.10 + pow(m, 60.0) * 0.22) * moon_vis * (1.0 - frame.rain * 0.5) * sun_glow * sky_k;
            }
        }
    }

    // Nether ash: small warm specks drifting upward, anchored to world space so they do not
    // stick to the camera when the player moves or turns.
    if (nether > 0.0) {
        // Fixed-depth anchor: the ash floats in the air in front of the camera, so turning the
        // camera gives real parallax instead of a layer stuck to the screen.
        let w = vpos_far + frame.camera_position;
        let cuv = vec2<f32>(w.x + w.y * 0.45, w.z) * 0.55 + vec2<f32>(time * 0.015, -time * 0.10);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.12) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let mote = 1.0 - smoothstep(0.0, 0.03 + h.y * 0.03, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 2.0 + h.y * 25.0);
            c += vec3<f32>(1.0, 0.50, 0.20) * mote * tw * nether * 0.35;
        }
    }

    // Cave dust: 1 cell only
    if (effect_cave_dust && cave_dust > 0.0) {
        let cave = 1.0 - smoothstep(0.02, 0.28, frame.eye_light.y);
        if (cave > 0.01) {
            let cells = 22.0 * (effect_dust_density * cave_dust);
            let cell_uv = input.uv * cells + vec2<f32>(time * 0.07, time * 0.045);
            let id = floor(cell_uv);
            let f = fract(cell_uv);
            let h = hash2(id);
            if (h.x < 0.18 * (effect_dust_density * cave_dust)) {
                let center = 0.5 + (h - 0.5) * 0.6;
                let dd = length(f - center);
                let mote = 1.0 - smoothstep(0.0, 0.02 + h.y * 0.02, dd);
                let tw = 0.6 + 0.4 * sin(time * 2.5 + h.y * 20.0);
                let fade = smoothstep(0.02, 0.15, d) * (1.0 - smoothstep(0.55, 0.95, d));
                c += vec3<f32>(0.82, 0.78, 0.70) * mote * tw * cave * fade * 0.45 * (effect_dust_intensity * cave_dust);
            }
        }
    }

    // Underwater: depth absorbs red first, so far water turns teal-blue; soft light shafts from
    // above and drifting specks. Only when the eye is in water. Strength: Underwater intensity.
    if (effect_underwater && underwater > 0.0 && frame.eye_in == 1u) {
        let k = (effect_underwater_intensity * underwater);
        let vpw = view_position(input.uv, select(0.5, d, d > 0.0));
        let dist_w = min(select(40.0, length(vpw), d > 0.0), 80.0);
        let trans = exp(-dist_w * vec3<f32>(0.04, 0.018, 0.008) * k);
        let murk_col = vec3<f32>(0.10, 0.40, 0.50);
        c = c * trans + murk_col * (vec3<f32>(1.0) - trans);
        c = mix(c, murk_col, 0.25 * underwater);

        let wxz = vpw.xz + frame.camera_position.xz;
        let t = time;
        let near_w = exp(-dist_w * 0.04);

        let shaft = smoothstep(0.55, 0.85, value_noise2(vec2<f32>(wxz.x * 0.25 + t * 0.02, wxz.y * 0.06)));
        c += vec3<f32>(0.50, 0.90, 1.00) * shaft * near_w * 0.025 * k;

        let cuv = input.uv * vec2<f32>(44.0, 28.0) + vec2<f32>(0.0, -time * 0.05);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let speck = 1.0 - smoothstep(0.0, 0.03 + h.y * 0.03, length(f - center));
            c += vec3<f32>(0.60, 0.90, 1.00) * speck * near_w * 0.12 * k;
        }
    }

    // ---------- Ambient world effects (all math-based, no textures) ----------

    // End motes: violet dust drifting through the void, anchored to world space.
    if (is_end && end_motes > 0.0) {
        let vpe = vpos_far;
        let we = vpe + frame.camera_position;
        let cuv = vec2<f32>(we.x + we.y * 0.35, we.z) * 0.7 + vec2<f32>(time * 0.03, -time * 0.05);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.16) {
            let center = 0.5 + (h - 0.5) * 0.7;
            let mote = 1.0 - smoothstep(0.0, 0.02 + h.y * 0.03, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 1.6 + h.y * 30.0);
            c += vec3<f32>(0.72, 0.45, 1.0) * mote * tw * end_motes * 0.30;
        }
    }

    // Nether portal shimmer: heat distortion of the colour, mathematical noise, warm pulse.
    if (is_nether && (nether_portal_glow * nether_fx) > 0.0) {
        let shimmer = value_noise2(input.uv * vec2<f32>(18.0, 12.0) + vec2<f32>(0.0, time * 0.6));
        c = c * (1.0 + (shimmer - 0.5) * 0.12 * (nether_portal_glow * nether_fx));
        let pulse = 0.5 + 0.5 * sin(time * 1.2 + shimmer * 6.0);
        c += vec3<f32>(0.55, 0.18, 0.9) * pulse * (nether_portal_glow * nether_fx) * 0.02;
    }

    // Fireflies: soft pulsing lights at night, world-locked.
    if ((fireflies * night_glow) > 0.0 && day < 0.35 && frame.eye_in == 0u && !is_nether && !is_end) {
        let vpf = vpos_far;
        let wf = vpf + frame.camera_position;
        let cuv = vec2<f32>(wf.x + wf.y * 0.2, wf.z) * 0.9 + vec2<f32>(time * 0.05, time * 0.03);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.7;
            let glow = 1.0 - smoothstep(0.0, 0.10, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 2.4 + h.y * 40.0);
            c += vec3<f32>(0.75, 1.0, 0.45) * glow * glow * tw * (fireflies * night_glow) * 0.5 * (1.0 - day);
        }
    }

    // Sparkles: tiny bright twinkles in the air (allay/sculk-like), world-locked.
    if (sparkles > 0.0) {
        let vps = vpos_far;
        let ws = vps + frame.camera_position;
        let cuv = vec2<f32>(ws.x + ws.y * 0.5, ws.z) * 1.4 + vec2<f32>(time * 0.12, -time * 0.09);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.07) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let r = length(f - center);
            let star = 1.0 - smoothstep(0.0, 0.035, r);
            let cross = max(1.0 - smoothstep(0.0, 0.006, abs(f.x - center.x)),
                           1.0 - smoothstep(0.0, 0.006, abs(f.y - center.y)));
            let tw = 0.5 + 0.5 * sin(time * 3.0 + h.y * 50.0);
            c += vec3<f32>(1.0, 0.95, 0.7) * (star + cross * 0.6) * tw * sparkles * 0.35;
        }
    }

    // Sculk pulse: dark cyan waves spreading from the view centre (Sculk-like heartbeat).
    if (is_end || ((sculk_pulse * dark_glow) > 0.0 && frame.eye_light.y < 0.15 && !is_nether)) {
        if ((sculk_pulse * dark_glow) > 0.0) {
            let vpl = vpos_far;
            let wl = vpl + frame.camera_position;
            let dist = length(wl.xz + wl.y * 0.3);
            let wave = 0.5 + 0.5 * sin(dist * 0.9 - time * 2.2);
            let ring = smoothstep(0.6, 1.0, wave) * smoothstep(60.0, 8.0, dist);
            c += vec3<f32>(0.1, 0.6, 0.65) * ring * (sculk_pulse * dark_glow) * 0.05 * (1.0 - smoothstep(0.1, 0.4, frame.eye_light.y));
        }
    }

    // ---------- Ambient sprite effects (textures generated for this pack) ----------

    // Falling leaves: spin and drift down through the world, tinted by the daylight.
    if ((leaf_fall * air_particles) > 0.0 && frame.eye_in == 0u && !is_nether && !is_end) {
        let vpl = vpos_far;
        let wl = vpl + frame.camera_position;
        let cuv = vec2<f32>(wl.x + wl.y * 0.3, wl.z) * 0.40 + vec2<f32>(time * 0.07, time * 0.24);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.13) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let p = (f - center) * 3.6;
            let rot = time * (0.7 + h.y * 1.5) + h.y * 10.0;
            let cs = cos(rot); let sn = sin(rot);
            let pr = vec2<f32>(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
            let t = textureSampleLevel(leaf, leaf_sampler, pr * 0.5 + 0.5, 0.0);
            if (t.a > 0.02) {
                let light_k = 0.45 + 0.55 * day;
                c = mix(c, t.rgb * light_k, t.a * (leaf_fall * air_particles) * 0.85);
            }
        }
    }

    // Drifting smoke: soft puffs rising slowly, world-locked.
    if ((air_smoke * air_particles) > 0.0 && frame.eye_in == 0u && !is_nether) {
        let vps2 = vpos_far;
        let ws2 = vps2 + frame.camera_position;
        let cuv = vec2<f32>(ws2.x + ws2.y * 0.15, ws2.z) * 0.30 + vec2<f32>(time * 0.03, -time * 0.12);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.5;
            let p = (f - center) * 3.2;
            let t = textureSampleLevel(smoke, smoke_sampler, p * 0.5 + 0.5, 0.0);
            if (t.a > 0.01) {
                let fade = smoothstep(0.05, 0.35, d) * (1.0 - smoothstep(0.6, 0.95, d));
                c = mix(c, t.rgb * (0.6 + 0.4 * day), t.a * (air_smoke * air_particles) * 0.35 * fade);
            }
        }
    }

    // Rising bubbles: round outlines floating up (underwater or in the air near water).
    if (bubbles > 0.0) {
        let vpb = vpos_far;
        let wb = vpb + frame.camera_position;
        let cuv = vec2<f32>(wb.x + wb.y * 0.5, wb.z) * 0.9 + vec2<f32>(0.0, -time * 0.35);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.09) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let p = (f - center) * 3.0;
            let t = textureSampleLevel(bubble, bubble_sampler, p * 0.5 + 0.5, 0.0);
            if (t.a > 0.01) {
                let under = select(0.4, 1.0, frame.eye_in == 1u);
                c = mix(c, vec3<f32>(0.75, 0.92, 1.0), t.a * bubbles * 0.45 * under);
            }
        }
    }

    // Floating runes: enchanting-table glyphs drifting in dark places.
    if ((runes * dark_glow) > 0.0 && frame.eye_light.y < 0.3) {
        let vpr = vpos_far;
        let wr = vpr + frame.camera_position;
        let cuv = vec2<f32>(wr.x + wr.y * 0.4, wr.z) * 0.7 + vec2<f32>(time * 0.05, -time * 0.08);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.08) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let p = (f - center) * 3.4;
            let rot = time * 0.4 + h.y * 6.28;
            let cs = cos(rot); let sn = sin(rot);
            let pr = vec2<f32>(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
            let t = textureSampleLevel(rune, rune_sampler, pr * 0.5 + 0.5, 0.0);
            if (t.a > 0.01) {
                let tw = 0.6 + 0.4 * sin(time * 2.0 + h.y * 30.0);
                let fade = 1.0 - smoothstep(0.1, 0.35, frame.eye_light.y);
                c += t.rgb * t.a * (runes * dark_glow) * 0.5 * tw * fade;
            }
        }
    }

    // Campfire sparks: tiny orange embers rising fast, world-locked.
    if ((sparks * air_particles) > 0.0) {
        let vpk = vpos_far;
        let wk = vpk + frame.camera_position;
        let cuv = vec2<f32>(wk.x + wk.y * 0.6, wk.z) * 1.6 + vec2<f32>(time * 0.05, -time * 0.9);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.09) {
            let center = 0.5 + (h - 0.5) * 0.5;
            let p = (f - center) * 6.0;
            let d2 = dot(p, p);
            let ember = exp(-d2 * 3.0);
            let tw = 0.4 + 0.6 * sin(time * 6.0 + h.y * 40.0);
            let fade = smoothstep(0.03, 0.2, d);
            c += vec3<f32>(1.0, 0.55, 0.15) * ember * tw * (sparks * air_particles) * 0.5 * fade;
        }
    }

    // Rain splash: quick bright rings hitting the ground while it rains.
    if (frame.rain > 0.3 && d > 0.0) {
        let vps3 = view_position(input.uv, d);
        let ws3 = vps3 + frame.camera_position;
        let cuv = vec2<f32>(ws3.x, ws3.z) * 1.2 + vec2<f32>(time * 0.4, time * 0.31);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.14) {
            let phase = fract(time * 1.4 + h.y);
            let rr = phase * 0.45;
            let dist = length(f - 0.5);
            let ring = 1.0 - smoothstep(0.0, 0.06, abs(dist - rr));
            let fade = 1.0 - phase;
            c += vec3<f32>(0.7, 0.8, 0.9) * ring * fade * frame.rain * 0.35;
        }
    }

    // Crystal glow: amethyst-like violet pulsing light in dark caves.
    if ((crystal_glow * dark_glow) > 0.0 && frame.eye_light.y < 0.2 && !is_nether) {
        let vpc = vpos_far;
        let wc = vpc + frame.camera_position;
        let cuv = vec2<f32>(wc.x + wc.y * 0.4, wc.z) * 0.6 + vec2<f32>(time * 0.02, time * 0.015);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.12) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let dist = length(f - center);
            let glow = exp(-dist * 9.0);
            let pulse = 0.6 + 0.4 * sin(time * 1.6 + h.y * 25.0);
            let dark = 1.0 - smoothstep(0.05, 0.3, frame.eye_light.y);
            c += vec3<f32>(0.65, 0.4, 1.0) * glow * pulse * (crystal_glow * dark_glow) * 0.35 * dark;
        }
    }

    // Drips: small drops falling now and then (water/lava style), world-locked.
    if ((drips * air_particles) > 0.0 && d > 0.0) {
        let vpd = view_position(input.uv, d);
        let wd = vpd + frame.camera_position;
        let cuv = vec2<f32>(wd.x, wd.z) * 2.2 + vec2<f32>(0.0, time * 1.1);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.06) {
            let phase = fract(time * 0.8 + h.y);
            let px = 0.5 + (h.x - 0.03) * 4.0;
            let py = phase;
            let dd = length((f - vec2<f32>(px - floor(px), py)) * vec2<f32>(1.0, 0.5));
            let drop = 1.0 - smoothstep(0.0, 0.10, dd);
            let col = select(vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(1.0, 0.5, 0.2), is_nether);
            c += col * drop * (drips * air_particles) * 0.4;
        }
    }

    // Soul wisps: pale blue souls drifting slowly upward in dark places.
    if ((soul_wisps * dark_glow) > 0.0 && frame.eye_light.y < 0.3 && !is_end) {
        let vp2 = vpos_far;
        let w2 = vp2 + frame.camera_position;
        let cuv = vec2<f32>(w2.x + w2.y * 0.25, w2.z) * 0.55 + vec2<f32>(sin(time * 0.3 + w2.y * 0.1) * 0.1, -time * 0.14);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let p = (f - center) * 5.0;
            let body = exp(-dot(p, p) * 4.0);
            let tail = exp(-abs(p.x) * 6.0) * exp(-max(p.y, 0.0) * 3.0) * 0.5;
            let tw = 0.6 + 0.4 * sin(time * 2.0 + h.y * 30.0);
            let dark = 1.0 - smoothstep(0.05, 0.3, frame.eye_light.y);
            c += vec3<f32>(0.35, 0.75, 1.0) * (body + tail) * tw * (soul_wisps * dark_glow) * 0.35 * dark;
        }
    }

    // Frost sparkles: tiny ice crystals glinting in snowy biomes.
    if (frost > 0.0 && !is_nether && !is_end && frame.precipitation > 0.4 && frame.temperature < 0.2 && d > 0.0) {
        let vpf2 = view_position(input.uv, d);
        let wf2 = vpf2 + frame.camera_position;
        let cuv = vec2<f32>(wf2.x + wf2.y * 0.5, wf2.z) * 1.8 + vec2<f32>(time * 0.03, time * 0.02);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let p = f - center;
            let cross = max(1.0 - smoothstep(0.0, 0.02, abs(p.x)),
                           1.0 - smoothstep(0.0, 0.02, abs(p.y)));
            let tw = 0.5 + 0.5 * sin(time * 4.0 + h.y * 60.0);
            c += vec3<f32>(0.85, 0.95, 1.0) * cross * tw * frost * 0.4;
        }
    }

    // Sun dust: golden motes floating in the air, brightest around sunset.
    if (sun_dust > 0.0 && day > 0.4 && frame.eye_in == 0u && !is_nether && !is_end) {
        let vps4 = vpos_far;
        let ws4 = vps4 + frame.camera_position;
        let cuv = vec2<f32>(ws4.x + ws4.y * 0.3, ws4.z) * 1.1 + vec2<f32>(time * 0.04, -time * 0.03);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.11) {
            let center = 0.5 + (h - 0.5) * 0.7;
            let mote = 1.0 - smoothstep(0.0, 0.035, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 1.2 + h.y * 35.0);
            c += vec3<f32>(1.0, 0.9, 0.65) * mote * tw * sun_dust * 0.22 * day;
        }
    }

    // Spores: warped/crimson-style spores drifting in the Nether.
    if (is_nether && (spores * nether_fx) > 0.0) {
        let vps5 = vpos_far;
        let ws5 = vps5 + frame.camera_position;
        let cuv = vec2<f32>(ws5.x + ws5.y * 0.4, ws5.z) * 0.8 + vec2<f32>(time * 0.06, -time * 0.16);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.12) {
            let center = 0.5 + (h - 0.5) * 0.6;
            let sp = 1.0 - smoothstep(0.0, 0.05 + h.y * 0.03, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 1.8 + h.y * 28.0);
            let col = select(vec3<f32>(1.0, 0.45, 0.7), vec3<f32>(0.3, 0.95, 0.85), h.y > 0.5);
            c += col * sp * tw * (spores * nether_fx) * 0.30;
        }
    }

    // Moon motes: cool silver dust at night.
    if ((moon_motes * night_glow) > 0.0 && day < 0.3 && frame.eye_in == 0u && !is_nether && !is_end) {
        let vpm = vpos_far;
        let wm = vpm + frame.camera_position;
        let cuv = vec2<f32>(wm.x + wm.y * 0.25, wm.z) * 0.95 + vec2<f32>(-time * 0.03, -time * 0.04);
        let id = floor(cuv);
        let f = fract(cuv);
        let h = hash2(id);
        if (h.x < 0.10) {
            let center = 0.5 + (h - 0.5) * 0.7;
            let mote = 1.0 - smoothstep(0.0, 0.04, length(f - center));
            let tw = 0.5 + 0.5 * sin(time * 1.0 + h.y * 45.0);
            c += vec3<f32>(0.7, 0.8, 1.0) * mote * tw * (moon_motes * night_glow) * 0.25 * (1.0 - day);
        }
    }

    // Bloom: 4 bilinear taps on one ring (off by default).
    if (bloom_on) {
        let px = 6.0 / frame.resolution;
        var sum = vec3<f32>(0.0);
        var wsum = 0.0;
        for (var i = 0; i < 4; i++) {
            let a = f32(i) * 1.570796;
            let t = bloom_tap(input.uv + vec2<f32>(cos(a), sin(a)) * px);
            sum += t.rgb * t.w;
            wsum += t.w;
        }
        c += (sum / max(wsum, 1.0e-4)) * (0.45 * bloom_strength * (1.0 + 0.5 * nether));
    }


    // Godray shafts: light shafts from the sun's screen position. Each pixel marches towards the sun over the
    // scene colour: bright pixels (sky, clouds, lit ground) pass light, dark pixels block it. Jittered start
    // per pixel to hide banding. Separate from the sky halo; strength is the Godray shafts option.
    // Cheap gate: if the sun is more than 90 degrees from the screen centre it cannot be on screen, so skip the search.
    let centre_dir = normalize(view_position(vec2<f32>(0.5, 0.5), 0.5));
    // No godrays when the camera has no sky light (underground, in a cave).
    if (godray_shafts > 0.0 && d <= 0.0 && sun_vis > 0.0 && sd > 0.1 && dot(centre_dir, frame.sun_direction) > 0.0 && frame.eye_light.y > 0.1) {
        let suv = sun_uv_screen();
        let in_view = smoothstep(-0.15, 0.0, suv.x) * smoothstep(-0.15, 0.0, 1.0 - suv.x)
                    * smoothstep(-0.15, 0.0, suv.y) * smoothstep(-0.15, 0.0, 1.0 - suv.y);
        if (in_view > 0.0) {
            let to_sun = suv - input.uv;
            let jit = hash2(input.uv * frame.resolution).x;
            var shaft = 0.0;
            var wsum = 0.0;
            var wgt = 1.0;
            for (var i = 0; i < 12; i = i + 1) {
                let tt = (f32(i) + jit) / 12.0;
                let sp = clamp(input.uv + to_sun * tt * 0.85, vec2<f32>(0.0), vec2<f32>(1.0));
                let scol = textureSampleLevel(previous, linear_sampler, sp, 0.0).rgb;
                shaft += smoothstep(0.45, 0.95, luma(scol)) * wgt;
                wsum += wgt;
                wgt = wgt * 0.94;
            }
            shaft = shaft / max(wsum, 1.0e-4);
            let toward = smoothstep(0.1, 0.9, sd);
            let wat = select(1.0, 0.6, frame.eye_in == 1u);
            c += glow_col * shaft * in_view * toward * sun_vis * (1.0 - frame.rain * 0.8) * godray_shafts * 0.30 * wat;
        }
    }

    // Lens flare: optical ghosts aligned with the projected sun direction.
    // Its anchor comes only from frame.sun_direction projected into screen UVs;
    // it does not use camera position as an effect origin.
    if (lens_flare > 0.0 && d <= 0.0 && sun_vis > 0.0 && sd > 0.15 && frame.rain < 0.8) {
        let suv = sun_uv_screen();
        let in_view = smoothstep(-0.12, 0.02, suv.x) * smoothstep(-0.12, 0.02, 1.0 - suv.x)
                    * smoothstep(-0.12, 0.02, suv.y) * smoothstep(-0.12, 0.02, 1.0 - suv.y);
        if (in_view > 0.0) {
            let axis = vec2<f32>(0.5, 0.5) - suv;
            let from_sun = input.uv - suv;
            let axis_len = max(length(axis), 1.0e-4);
            let axis_dir = axis / axis_len;
            let radial = length(from_sun);
            let halo = exp(-radial * 34.0) * 0.18 + exp(-radial * 11.0) * 0.035;
            let streak_dist = abs(dot(from_sun, vec2<f32>(-axis_dir.y, axis_dir.x)));
            let streak = exp(-streak_dist * 900.0) * exp(-radial * 5.0) * 0.035;
            var ghosts = 0.0;
            for (var i = 0; i < 2; i = i + 1) {
                let t = 0.35 + f32(i) * 0.28;
                let gp = suv + axis * t;
                let r = length(input.uv - gp);
                let size = 0.018 + f32(i) * 0.006;
                ghosts += exp(-r / size) * (0.035 / (1.0 + f32(i) * 0.5));
            }
            let flare_col = mix(vec3<f32>(0.55, 0.72, 1.0), glow_col, 0.72);
            let flare = (halo + streak) * flare_intensity + ghosts * flare_ghosts;
            c += flare_col * flare * lens_flare * in_view * (1.0 - frame.rain * 0.75);
        }
    }

    c = c * (1.0 - vignette * smoothstep(0.45, 1.0, length(input.uv - vec2<f32>(0.5)) * 1.414));
    c = apply_tonemap(c);
    c = purkinje_effect(c, 1.0 - max(frame.eye_light.x, frame.eye_light.y));
    c = final_grade(c);
    return vec4<f32>(c, input.color.a);
}
