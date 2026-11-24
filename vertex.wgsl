/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
// Plant motion. The material ids come from the [[materials]] entries in horizon-shaders.toml.
// Only sprites listed there move; grass blocks, dirt and stone stay put.
//
// How a corner is anchored. `1 - uv.y` is the corner's height inside its own sprite: 0 at the
// foot, 1 at the tip. Three cases, and they must not be mixed up:
//
//   1. one-block plants (grass, ferns, flowers, seagrass): the foot is pinned and the tip bends,
//      so displacement grows with that height;
//   2. two-block plants (tall grass, large fern, sunflower, tall seagrass): the lower sprite's
//      tip and the upper sprite's foot must move by the SAME amount, or the plant tears in half
//      at the seam. Lower moves 0.045 * top (tip = 0.045), upper moves 0.045 + 0.045 * top
//      (foot = 0.045), so the two edges meet exactly;
//   3. kelp: one block of kelp is drawn as its own cross quads and the stage cannot know how tall
//      the column is, so there is no per-column foot to pin. Anchoring each block's own foot
//      (case 1) tore every seam open: the top of one block moved while the bottom of the next
//      stayed put, which is the broken seaweed mesh. Kelp therefore gets the SAME amount for
//      every corner of the block, with the phase (not the amplitude) changing with world height.
//      Two corners that share a world position get the same offset, so a seam can never open,
//      while the different height above and below still bends the segment.

const VM_LEAVES: u32 = 1u;
const VM_PLANT: u32 = 2u;
const VM_TALL_LOWER: u32 = 3u;
const VM_TALL_UPPER: u32 = 4u;
const VM_KELP: u32 = 5u;
const VM_SEAGRASS: u32 = 6u;
const VM_SEAGRASS_LOWER: u32 = 7u;
const VM_SEAGRASS_UPPER: u32 = 8u;
const VM_LAST: u32 = 8u;

// Water plants move less and on a slower beat: the water is heavy.
const WET_SLOW: f32 = 0.55;

// Sway at world point p: two sines at different speeds, varying across the land. The height term
// lets a tall plant bend along its column instead of sliding as a rigid cross.
fn plant_wind(p: vec3<f32>, t: f32) -> vec3<f32> {
    let ph = p.x * 0.8 + p.z * 0.6 + p.y * 0.35;
    let gust = 0.7 + 0.3 * sin(t * 0.3 + p.x * 0.05);
    let x = sin(t * 2.0 + ph) * 0.6 + sin(t * 3.4 + ph * 1.5) * 0.4;
    let z = sin(t * 1.7 + ph * 1.2 + 1.0) * 0.6 + sin(t * 3.9 + p.z) * 0.2;
    return vec3<f32>(x, 0.0, z) * gust;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    let m = input.material;
    if (wind_plants <= 0.0 || m == 0u || m > VM_LAST) {
        return p;
    }

    let world = p + frame.camera_position;
    let wet = m >= VM_KELP;

    // Sheltered plants hardly move, and rain stirs them more. Water plants keep a floor, because
    // kelp under an overhang still drifts with the current rather than freezing in place.
    let exposure = select(smoothstep(0.2, 0.9, input.light.y), mix(0.45, 1.0, smoothstep(0.0, 0.9, input.light.y)), wet);
    let t = select(frame.time, frame.time * WET_SLOW, wet);

    let w = plant_wind(world, t) * wind_plants * exposure * (1.0 + frame.rain * 0.6);
    // 0 at the foot, 1 at the tip; squared so the bend starts softly and the plant keeps its base.
    let top = clamp(1.0 - input.uv.y, 0.0, 1.0);
    let bend = top * top;

    switch m {
        case VM_LEAVES: {
            // A leaf block is a cube: every corner moves together, a couple of centimetres.
            p = p + w * 0.02;
        }
        case VM_PLANT: {
            p = p + w * (0.10 * bend);
        }
        case VM_TALL_LOWER: {
            p = p + w * (0.045 * top);
        }
        case VM_TALL_UPPER: {
            p = p + w * (0.045 + 0.045 * top);
        }
        case VM_KELP: {
            // No per-column foot to pin: same amount on every corner, so both sides of a seam
            // agree (see case 3 above).
            p = p + w * 0.03;
        }
        case VM_SEAGRASS: {
            p = p + w * (0.07 * bend);
        }
        case VM_SEAGRASS_LOWER: {
            p = p + w * (0.035 * top);
        }
        case VM_SEAGRASS_UPPER: {
            p = p + w * (0.035 + 0.035 * top);
        }
        default: {
        }
    }
    return p;
}
