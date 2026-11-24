/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Pass 1 of 3: outlines.
//  - depth edges: a jump in distance relative to the distance itself, no matrices;
//  - colour edges: a strong brightness step next to a small depth step, which is what the
//    silhouette of an entity looks like against the ground behind it (textures alone, with no depth
//    step, never draw a line, so grass and leaves stay clean);
//  - near objects get thicker lines and an ink tone (dark version of their own colour); far ones
//    keep the bright coloured line.
fn rel_jump(c: f32, uv: vec2<f32>) -> f32 {
    let d = depth_at(uv);
    if (d <= 0.0) { return 1.0; }
    return min(abs(c / d - 1.0), 1.0);
}

fn lum_at(uv: vec2<f32>) -> f32 {
    return luma(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
}

fn post(input: PostInput) -> vec4<f32> {
    let base = input.color;
    if (!outlines || input.depth <= 0.0) { return base; }

    let dist = length(view_position(input.uv, input.depth));
    // Outlines fade out with distance (Outline range option), so far lines do not show through the fog.
    let outline_fade = 1.0 - smoothstep(outline_range * 0.6, outline_range, dist);
    if (outline_fade <= 0.0) { return base; }
    let near_k = 1.0 - smoothstep(4.0, 18.0, dist);
    // Merged controls: outline_strength scales the line, outline_look scales colour and fade.
    let o_int = outline_intensity * outline_strength;
    let o_sat = 1.0 + (outline_saturation - 1.0) * outline_look;
    let o_bri = 1.0 + (outline_brightness - 1.0) * outline_look;
    let o_fade = outline_distance_fade * outline_look;
    let o_edge = outline_color_edges * outline_look;
    let o_ink = outline_ink * outline_look;
    let thick = f32(outline_thickness) * (1.0 + near_k * outline_near_boost);
    let px = thick / frame.resolution;

    let c = input.depth;
    let jr = rel_jump(c, input.uv + vec2<f32>(px.x, 0.0));
    let jl = rel_jump(c, input.uv - vec2<f32>(px.x, 0.0));
    let ju = rel_jump(c, input.uv + vec2<f32>(0.0, px.y));
    let jd = rel_jump(c, input.uv - vec2<f32>(0.0, px.y));
    let edge = max(max(jr, jl), max(ju, jd));

    let soft = max(outline_softness * outline_threshold * 2.0, 1.0e-4);
    var k = smoothstep(outline_threshold, outline_threshold + soft, edge);

    // Colour edge, only where there is at least a faint depth step.
    if (o_edge > 0.0 && edge > outline_threshold * 0.3) {
        let l0 = luma(base.rgb);
        let dl = max(max(abs(lum_at(input.uv + vec2<f32>(px.x, 0.0)) - l0), abs(lum_at(input.uv - vec2<f32>(px.x, 0.0)) - l0)),
                     max(abs(lum_at(input.uv + vec2<f32>(0.0, px.y)) - l0), abs(lum_at(input.uv - vec2<f32>(0.0, px.y)) - l0)));
        let ck = smoothstep(0.12, 0.40, dl)
               * smoothstep(outline_threshold * 0.3, outline_threshold, edge)
               * o_edge * (0.4 + 0.6 * near_k);
        k = max(k, ck);
    }

    k = k * (1.0 - o_fade * smoothstep(48.0, 192.0, dist));
    k = clamp(k * o_int, 0.0, 1.0);

    let bright = clamp(apply_saturation(base.rgb, o_sat) * o_bri,
                       vec3<f32>(0.0), vec3<f32>(1.0));
    let ink = base.rgb * 0.30;
    let line = mix(bright, ink, o_ink * near_k);
    return vec4<f32>(mix(base.rgb, line, k * outline_fade), base.a);
}
