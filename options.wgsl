/*
 * kefs simplicity shader
 * Copyright (c) 2026 VEKIIXX
 * Modificações permitidas desde que mantenham os créditos originais a VEKIIXX e não contenham código malicioso.
 */
override tonemap_op: u32 = 3u;
override exposure: f32 = 1.15;
override saturation: f32 = 1.25;
override vibrance: f32 = 0.30;
override contrast: f32 = 1.08;
override gamma_adjust: f32 = 1.05;
override scene_brightness: f32 = -0.05;
override scene_darkness: f32 = 0.05;
override purkinje: f32 = 0.35;

override outlines: bool = true;
override outline_intensity: f32 = 1.25;
override outline_threshold: f32 = 0.022;
override outline_softness: f32 = 0.90;
override outline_saturation: f32 = 1.60;
override outline_brightness: f32 = 1.25;
override outline_thickness: i32 = 1;
override outline_distance_fade: f32 = 0.35;

override bloom_on: bool = false;
override bloom_strength: f32 = 1.20;

override water_style: u32 = 1u;
override water_cell_density: f32 = 0.90;
override water_cell_speed: f32 = 1.00;
override water_cells_still: f32 = 1.00;
override water_flow_streaks: f32 = 0.50;

override effect_cave_dust: bool = true;
override effect_dust_density: f32 = 1.0;
override effect_dust_intensity: f32 = 1.0;
override effect_underwater: bool = true;
override effect_underwater_intensity: f32 = 1.0;

override vivid_sunset: f32 = 0.60;
override night_sky: bool = true;

override water_shore: bool = true;
override water_shore_width: f32 = 1.0;

override toon_light: f32 = 0.40;
override sun_warmth: f32 = 1.15;
override atmo_haze: f32 = 0.70;

override outline_color_edges: f32 = 0.80;
override outline_near_boost: f32 = 1.0;
override outline_ink: f32 = 0.50;
override sun_glow: f32 = 0.80;
override godrays: f32 = 0.70;
override godray_shafts: f32 = 0.75;
override lens_flare: f32 = 0.65;
override flare_intensity: f32 = 0.45;
override flare_ghosts: f32 = 0.25;
override nether_fog: f32 = 1.0;
override warm_horizon: f32 = 1.0;
override dust_storm: f32 = 0.6;
override biome_mood: f32 = 1.0;
override biome_fog_density: f32 = 1.0;
override ground_fog: f32 = 0.35;
override vignette: f32 = 0.25;
override split_tone: f32 = 0.35;

override ao_strength: f32 = 0.6;
override calc_radius: f32 = 100.0;
override bloom_masks: f32 = 1.0;
override meteor_shower: f32 = 0.6;
override aurora: f32 = 0.7;
override wind_plants: f32 = 1.0;
override caustics: f32 = 0.5;
override subsurface: f32 = 0.5;
override sun_specular: f32 = 0.4;
override rim_light: f32 = 0.6;

override outline_range: f32 = 120.0;

// Merged group controls (see horizon-shaders.toml pages).
// Each one multiplies the individual effects that share the same place / environment,
// so one slider moves a whole group without breaking the per-effect defaults.
override scene_light: f32 = 0.0;
override outline_strength: f32 = 1.0;
override outline_look: f32 = 1.0;
override water_motion: f32 = 1.0;
override cave_dust: f32 = 1.0;
override underwater: f32 = 1.0;
override biome_fog: f32 = 1.0;
override desert_atmo: f32 = 1.0;
override air_particles: f32 = 0.6;
override night_glow: f32 = 0.6;
override dark_glow: f32 = 0.5;
override nether_fx: f32 = 0.6;

// Ambient world effects (math-based)
override end_motes: f32 = 0.7;
override nether_portal_glow: f32 = 0.83;
override fireflies: f32 = 1.0;
override sparkles: f32 = 0.5;
override sculk_pulse: f32 = 0.8;

// Lighting controls
override vanilla_shadows: f32 = 0.0;

// Ambient sprite effects
override leaf_fall: f32 = 1.17;
override air_smoke: f32 = 0.83;
override bubbles: f32 = 0.5;
override runes: f32 = 1.0;
override sparks: f32 = 1.0;
override crystal_glow: f32 = 1.0;
override drips: f32 = 0.83;
override soul_wisps: f32 = 1.0;
override frost: f32 = 0.5;
override sun_dust: f32 = 0.6;
override spores: f32 = 1.0;
override moon_motes: f32 = 0.83;

