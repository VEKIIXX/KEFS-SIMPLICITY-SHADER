/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Material for Horizon: water + shoreline, warm/cool toon lighting, pixel shadows.
//
// Shadows: 1024 map ([shadow]), 4 soft taps.

fn sample_shadow(world_pos: vec3<f32>, bias_n: vec3<f32>) -> f32 {
    if (frame.has_shadow == 0u) { return 1.0; }
    // Beyond the calculation radius the shadow is not computed at all.
    if (length(world_pos) > calc_radius) { return 1.0; }
    // Bias in texels: one texel is about 96 / resolution blocks.
    let tw = 96.0 / max(frame.shadow_resolution, 1.0);
    let bias = bias_n * tw * 1.5 + frame.light_direction * tw;
    let sp = shadow_position(world_pos + bias);
    if (sp.x < 0.0 || sp.x > 1.0 || sp.y < 0.0 || sp.y > 1.0) { return 1.0; }
    // Far (past 30 blocks): one tap. Near: the original 2 taps.
    if (length(world_pos) > 30.0) {
        return textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
    }
    let t = 0.6 / max(frame.shadow_resolution, 1.0);
    var s = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
    s += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy + vec2<f32>(t, t), sp.z);
    return s * 0.5;
}

// Warm sun / cool shade, tinted by the time of day.
fn light_tint(shadow: f32, sky_light: f32) -> vec3<f32> {
    let elev = frame.sun_direction.y;
    let day = smoothstep(-0.18, 0.16, elev);
    let sunset = (1.0 - smoothstep(0.06, 0.30, elev)) * smoothstep(-0.18, -0.02, elev);
    let sun_col = mix(vec3<f32>(1.06, 1.00, 0.90), vec3<f32>(1.18, 0.78, 0.48), sunset);
    let shade_col = mix(vec3<f32>(0.62, 0.70, 0.96), vec3<f32>(0.62, 0.52, 0.84), sunset);
    let day_tint = mix(shade_col, sun_col, shadow);
    let night_tint = vec3<f32>(0.58, 0.68, 1.04);
    let tint = mix(night_tint, day_tint, day);
    return mix(vec3<f32>(1.0), mix(vec3<f32>(1.0), tint, clamp(sun_warmth, 0.0, 2.0) * 0.5), sky_light);
}

// Cel-style light: steps vanilla's light colour into bands, blended by toon_light.
fn toon(lm: vec3<f32>) -> vec3<f32> {
    let l = luma(lm);
    // Soft bands: each step blends over the middle of its band, so the lit shapes fade instead of cutting hard.
    let x = l * 5.0 + 0.5;
    let q = (floor(x) + smoothstep(0.30, 0.70, fract(x))) / 5.0;
    return mix(lm, lm * (q / max(l, 1.0e-3)), toon_light);
}

// ---- Nether portal depth -------------------------------------------------
// The portal is treated as a volume, not a flat sheet: a short raymarch walks
// layers into the portal plane and each layer samples a procedural purple
// swirl, so turning the camera shows real parallax inside the portal.
fn portal_hash(p: vec2<f32>) -> f32 { return hash2(p).x; }

fn portal_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = portal_hash(i);
    let b = portal_hash(i + vec2<f32>(1.0, 0.0));
    let c = portal_hash(i + vec2<f32>(0.0, 1.0));
    let d = portal_hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Slowly rotating plasma: the rotation angle itself comes from noise, so the
// swirl folds instead of just spinning as a whole.
fn portal_swirl(uv: vec2<f32>, t: f32) -> f32 {
    let c = uv - 0.5;
    let ang = 0.35 * t + portal_noise(uv * 3.0 + vec2<f32>(t * 0.12, 0.0)) * 3.5;
    let cs = cos(ang);
    let sn = sin(ang);
    let r = vec2<f32>(c.x * cs - c.y * sn, c.x * sn + c.y * cs) + 0.5;
    let n1 = portal_noise(r * 7.0 + vec2<f32>(0.0, t * 0.5));
    let n2 = portal_noise(r * 16.0 - vec2<f32>(t * 0.35, 0.0));
    return n1 * 0.70 + n2 * 0.45;
}

fn material(input: MaterialInput) -> Surface {
    var s: Surface;
    let is_water = input.fluid == 1u;

    if (!is_water) {
        let base = (input.albedo * input.tint).rgb;

        // Nether portal: a short parallax raymarch into the portal plane, so the
        // swirl sits at a real depth instead of being painted on the surface.
        if (input.material == 9u && (nether_portal_glow * nether_fx) > 0.0) {
            let pg = nether_portal_glow * nether_fx;
            // Tangent frame of this face, from screen derivatives of position and uv.
            let dpx = dpdx(input.position);
            let dpy = dpdy(input.position);
            let dux = dpdx(input.uv);
            let duy = dpdy(input.uv);
            let det = dux.x * duy.y - dux.y * duy.x;
            var tvec = vec3<f32>(1.0, 0.0, 0.0);
            var bvec = vec3<f32>(0.0, 1.0, 0.0);
            if (abs(det) > 1.0e-8) {
                tvec = (dpx * duy.y - dpy * dux.y) / det;
                bvec = (dpy * dux.x - dpx * duy.x) / det;
            }
            let nrm = normalize(cross(tvec, bvec));
            let vdir = normalize(-input.position);
            let vt = vec3<f32>(dot(vdir, tvec), dot(vdir, bvec), dot(vdir, nrm));
            // Step into the surface against the view: layers away from the camera.
            let step_uv = -vt.xy / max(abs(vt.z), 0.25) * 0.22;
            let dither = portal_hash(input.screen * 0.37 + vec2<f32>(frame.time, frame.time * 1.7));
            var acc = vec3<f32>(0.0);
            var wsum = 0.0;
            for (var i = 0; i < 12; i = i + 1) {
                let t = (f32(i) + dither) / 12.0;
                let luv = clamp(input.uv + step_uv * t, vec2<f32>(0.0), vec2<f32>(1.0));
                let dens = portal_swirl(luv, frame.time);
                let d = smoothstep(0.34, 0.95, dens) * (1.0 - 0.65 * t);
                let col = mix(vec3<f32>(0.30, 0.06, 0.72), vec3<f32>(0.78, 0.42, 1.0), d);
                acc += col * d;
                wsum += 1.0;
            }
            var col = acc / max(wsum, 1.0e-4) * 3.4;
            // Bright rim where the layers meet the edge of the portal block.
            let eu = max(abs(input.uv.x - 0.5), abs(input.uv.y - 0.5)) * 2.0;
            col += vec3<f32>(0.85, 0.60, 1.0) * pow(eu, 7.0) * 2.2;
            // Hot core where the swirl is densest.
            let core = smoothstep(0.80, 1.05, portal_swirl(input.uv, frame.time));
            col += vec3<f32>(1.0, 0.90, 1.0) * core * 1.4;
            col *= pg;
            // Push above 1.0 so selective bloom picks the portal up.
            s.color = vec4<f32>(col * (1.0 + bloom_masks * 0.9), input.albedo.a * input.tint.a);
            return s;
        }

        // Coloured block light: a gentle tint, only where the pixel actually gets block light
        // (input.light.x), so a lava pool or torch never paints distant snow red.
        let bl = block_light_color(input.position);
        let reach = smoothstep(0.05, 0.45, bl.a) * smoothstep(0.08, 0.60, input.light.x);
        let tint_c = mix(vec3<f32>(1.0), bl.rgb, 0.50 * reach);
        // Vanilla's lightmap carries the game's own baked shadows/AO. vanilla_shadows = 0 lifts
        // the dark levels (game shadows off, only this pack's shadow map shades), 1 keeps them.
        let lm_pow = mix(0.50, 1.0, clamp(vanilla_shadows, 0.0, 1.0));
        let lm = pow(max(input.lightmap, vec3<f32>(0.0)), vec3<f32>(lm_pow));
        var lit = base * toon(lm) * tint_c;
        // Shadow bias uses the face's real normal (from screen derivatives), not a fixed "up".
        // A constant up normal pushed the shadow test the wrong way on walls and slopes: the diagonal stripes.
        let sh_vdir = normalize(-input.position);
        let sh_n0 = normalize(cross(dpdx(input.position), dpdy(input.position)));
        let sh_n = select(sh_n0, -sh_n0, dot(sh_n0, sh_vdir) < 0.0);
        // Underground (no sky light): skip the shadow lookup entirely, nothing there is lit by the sun.
        var shadow = 1.0;
        if (input.light.y > 0.04) {
            shadow = sample_shadow(input.position, sh_n);
        }
        lit = lit * mix(0.74, 1.0, shadow) * light_tint(shadow, input.light.y);
        // Held and dropped items (and [[particle_lights]]) arrive in colored_light, 0..1, only while
        // Horizon Extras' dynamic lights are on. Add it as real light, not just a tint.
        lit = lit + base * input.colored_light * 0.9;
        // Rim light and specular features written for this pack.
        // Rim light: a soft sunward edge where the face turns away from the camera.
        let rim_ndv = clamp(dot(sh_n, sh_vdir), 0.0, 1.0);
        let rim_sun = smoothstep(-0.10, 0.30, dot(sh_n, frame.sun_direction));
        lit = lit + vec3<f32>(1.0, 0.95, 0.85) * pow(1.0 - rim_ndv, 3.0) * rim_sun * input.light.y * rim_light * 0.35;
        // Multi-pack inspiration (concepts only, all code written here):
        // leaf and grass backlight (subsurface scattering): green surfaces glow when the sun is behind them.
        // Sun specular on hard, non-plant surfaces (stone, wood): a tight sun glint, off on very bright surfaces (snow).
        let sss_day = smoothstep(-0.18, 0.16, frame.sun_direction.y) * (1.0 - frame.rain * 0.8);
        let plant_g = input.tint.rgb;
        let plant_k = smoothstep(0.02, 0.10, plant_g.g - max(plant_g.r, plant_g.b));
        let back_k = pow(clamp(dot(-sh_vdir, frame.sun_direction), 0.0, 1.0), 4.0)
                   * (1.0 - clamp(dot(sh_n, frame.sun_direction), 0.0, 1.0));
        lit = lit + base * vec3<f32>(1.0, 0.92, 0.70) * back_k * plant_k * subsurface * input.light.y * sss_day * shadow;
        // Sun glint: a tight specular ray of the sun on hard surfaces.
        let half_v = normalize(frame.sun_direction + sh_vdir);
        let spec = pow(clamp(dot(sh_n, half_v), 0.0, 1.0), 48.0);
        let not_snow = 1.0 - smoothstep(0.80, 0.93, luma(base));
        lit = lit + vec3<f32>(1.0, 0.95, 0.85) * spec * (1.0 - plant_k) * not_snow * sun_specular * shadow * input.light.y * sss_day;
        // Selective bloom: emissive blocks are pushed above 1.0 so the bloom threshold picks only them up.
        let emit_level = f32(input.emission);
        if (emit_level > 0.0) {
            lit = lit * (1.0 + bloom_masks * min(emit_level, 4.0) * 0.30);
        }
        // Underwater caustics (own pattern): light rippling on upward faces while the camera is underwater.
        if ((caustics * underwater) > 0.0 && f32(frame.eye_in) > 0.5 && sh_n.y > 0.6 && input.light.y > 0.1) {
            let cwp = (input.position + frame.camera_position).xz * 1.4;
            let ct = frame.time * 0.6;
            let c1 = abs(sin(cwp.x * 2.0 + sin(cwp.y * 1.7 + ct * 0.9) * 1.3 + ct * 0.5));
            let c2 = abs(sin(cwp.y * 2.3 + sin(cwp.x * 1.9 - ct * 0.7) * 1.1));
            let cline = smoothstep(0.80, 1.0, 1.0 - min(c1 * c2, 1.0));
            lit = lit + vec3<f32>(0.40, 0.90, 1.00) * cline * (caustics * underwater) * 0.35 * input.light.y * (sh_n.y - 0.6) * 2.5;
        }
        // Rounded clouds: vanilla draws clouds as translucent white terrain. Give them rounded
        // corners (alpha mask) and tint the high ones blue, so a blue layer sits above the white.
        let is_cloud = input.material == 0u && input.translucent
            && min(input.albedo.r, min(input.albedo.g, input.albedo.b)) > 0.78
            && (max(input.albedo.r, max(input.albedo.g, input.albedo.b)) - min(input.albedo.r, min(input.albedo.g, input.albedo.b))) < 0.12
            && input.light.y > 0.2;
        if (is_cloud) {
            let world_y = input.position.y + frame.camera_position.y;
            let high = smoothstep(100.0, 170.0, world_y);
            let blue_tint = mix(vec3<f32>(1.0), vec3<f32>(0.55, 0.72, 1.00), high * 0.60);
            lit = lit * blue_tint;
            // rounded corners (rounded box, radius 0.26 in uv space)
            let q = abs(input.uv - vec2<f32>(0.5)) * 2.0;
            let r = 0.26;
            let d = length(max(q - vec2<f32>(1.0 - r), vec2<f32>(0.0))) - r;
            let corner_mask = 1.0 - smoothstep(-0.04, 0.06, d);
            s.color = vec4<f32>(lit, input.albedo.a * input.tint.a * corner_mask);
            return s;
        }

        s.color = vec4<f32>(lit, input.albedo.a * input.tint.a);
        return s;
    }

    // ----- water -----
    let wp = input.position + frame.camera_position;
    let dx = dpdx(wp);
    let dy = dpdy(wp);
    var n = normalize(cross(dx, dy));
    if (n.y < 0.0) { n = -n; }
    if (length(cross(dx, dy)) < 1.0e-8) { n = vec3<f32>(0.0, 1.0, 0.0); }

    let footprint = max(length(dx.xz), length(dy.xz));
    let view_dist = length(input.position);
    let view = normalize(-input.position);
    let day = smoothstep(-0.18, 0.16, frame.sun_direction.y);
    let fresnel = pow(1.0 - clamp(dot(view, n), 0.0, 1.0), 3.0);
    let glint = day * (1.0 - frame.rain)
        * pow(max(dot(reflect(-view, n), frame.sun_direction), 0.0), 96.0);
    let flowness = select(1.0 - clamp(n.y * n.y, 0.0, 1.0), 0.0, input.face == 1u);

    var w: vec4<f32>;
    if (water_style == 1u) {
        let tint = mix(vec3<f32>(1.0), input.tint.rgb, 0.35);
        w = pixel_water_top(wp, frame.time, footprint, flowness, fresnel, day,
            frame.sun_direction.y, glint, frame.rain, tint);
    } else {
        w = anime_water_top(wp.xz, frame.time, footprint, flowness, fresnel, day, glint);
    }

    // Shoreline: how much water lies between the surface and the block behind it.
    if (water_shore) {
        // input.screen is read as a pixel position; a 0..1 value is scaled up.
        let spx = select(input.screen * frame.resolution, input.screen, input.screen.x > 1.5 || input.screen.y > 1.5);
        let od = textureLoad(opaque_depth, vec2<i32>(spx), 0);
        var thick = 8.0;
        if (od > 0.0) {
            let suv = spx / frame.resolution;
            let clip = vec4<f32>(suv.x * 2.0 - 1.0, 1.0 - suv.y * 2.0, od, 1.0);
            let vp = frame.projection_inverse * clip;
            let behind = length(vp.xyz / vp.w);
            thick = max(behind - view_dist, 0.0) * clamp(abs(view.y), 0.25, 1.0);
        }
        let foam = shore_foam(thick, wp, frame.time, day, view_dist, water_style == 1u);
        w = vec4<f32>(mix(w.rgb, foam.rgb, foam.a), max(w.a, foam.a));
    }

    let shadow = sample_shadow(input.position, n);
    let lit = w.rgb * max(toon(input.lightmap), vec3<f32>(0.12)) * mix(0.75, 1.0, shadow)
            * light_tint(shadow, input.light.y);
    s.color = vec4<f32>(lit, w.a);
    return s;
}
