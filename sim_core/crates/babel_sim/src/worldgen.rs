//! Initial world generation.
//!
//! Three independent noise layers — elevation, moisture, temperature — are
//! sampled per tile, then quantised into [`Biome`]s. Rivers are traced from
//! local-maxima down the elevation gradient. All RNG is forked from the
//! master so worldgen is deterministic and independent from later sim RNG
//! draws.

use noise::{NoiseFn, Perlin};

use crate::det_rng::DetRng;
use crate::event::EventKind;
use crate::world::{tile_tags, Biome, Tile, World, WorldDims};
use crate::SimResult;

/// Tunable knobs for worldgen. All numbers are deliberately deterministic and
/// have unit tests pinning their behaviour for the default config.
#[derive(Debug, Clone, Copy)]
pub struct WorldGenParams {
    /// Frequency of the elevation noise (smaller = bigger continents).
    pub elev_freq: f64,
    /// Frequency of the moisture noise.
    pub moist_freq: f64,
    /// Frequency of the temperature noise.
    pub temp_freq: f64,
    /// Target fraction of map covered by water (ocean + coast). The actual
    /// `sea_level` cutoff is computed from the elevation histogram so we
    /// always hit roughly this ratio. Range `0.0..=1.0`.
    pub sea_fraction: f32,
    /// Fraction of pre-existing ruins (Harrison: "inverted progression").
    pub ruin_density: f32,
    /// Number of "Zone" anomaly tiles (Strugatsky).
    pub zone_count: u32,
}

impl Default for WorldGenParams {
    fn default() -> Self {
        Self {
            elev_freq: 0.012,
            moist_freq: 0.020,
            temp_freq: 0.008,
            sea_fraction: 0.40,
            ruin_density: 0.005,
            zone_count: 8,
        }
    }
}

/// Run worldgen on `world.tiles`. The world is mutated in place. The master
/// RNG is forked once per layer so adding a future layer doesn't shift bits.
pub fn generate(world: &mut World, params: &WorldGenParams) -> SimResult<()> {
    let dims = world.dims;

    // Three independent forks — order matters but is fixed.
    let mut elev_rng = world.rng.fork();
    let mut moist_rng = world.rng.fork();
    let mut temp_rng = world.rng.fork();
    let mut feature_rng = world.rng.fork();

    let elev = Perlin::new(elev_rng.next_u32() & 0x7FFF_FFFF);
    let moist = Perlin::new(moist_rng.next_u32() & 0x7FFF_FFFF);
    let temp = Perlin::new(temp_rng.next_u32() & 0x7FFF_FFFF);

    // Pass 1: write elevation/moisture/temperature only.
    fill_unbiomed(&mut world.tiles, dims, &elev, &moist, &temp, params);
    // Pass 2: derive a sea level from the elevation histogram so we always
    // hit the configured `sea_fraction`.
    let sea_level = pick_sea_level(&world.tiles, params.sea_fraction);
    // Pass 3: assign biomes using the chosen sea level.
    assign_biomes(&mut world.tiles, sea_level);
    sprinkle_rivers(&mut world.tiles, dims);
    sprinkle_ruins(
        &mut world.tiles,
        dims,
        &mut feature_rng,
        params.ruin_density,
    );
    sprinkle_zones(&mut world.tiles, dims, &mut feature_rng, params.zone_count);

    world
        .events
        .push(world.clock.ticks(), EventKind::WorldGenerated { seed: 0 });
    Ok(())
}

fn fill_unbiomed(
    tiles: &mut [Tile],
    dims: WorldDims,
    elev: &Perlin,
    moist: &Perlin,
    temp: &Perlin,
    params: &WorldGenParams,
) {
    let WorldDims { w, h } = dims;
    let h_f = f64::from(h);
    for y in 0..h {
        for x in 0..w {
            let fx = f64::from(x);
            let fy = f64::from(y);
            let e = sample_octaves(elev, fx * params.elev_freq, fy * params.elev_freq, 4);
            let m = sample_octaves(moist, fx * params.moist_freq, fy * params.moist_freq, 3);
            // Temperature falls off near the poles (top + bottom of map).
            let lat = 1.0 - (2.0 * fy / h_f - 1.0).abs(); // 1.0 equator, 0.0 poles
            let t_v = sample_octaves(temp, fx * params.temp_freq, fy * params.temp_freq, 2) * 0.5
                + lat * 0.5;

            let i = y as usize * w as usize + x as usize;
            let t = &mut tiles[i];
            t.elevation = unit_to_u8(e);
            t.moisture = unit_to_u8(m);
            t.temperature = unit_to_u8(t_v);
        }
    }
}

/// Pick the elevation cutoff such that approximately `sea_fraction` of tiles
/// are below it. Computed via a 256-bucket histogram so it's O(n) regardless
/// of map size.
fn pick_sea_level(tiles: &[Tile], sea_fraction: f32) -> u8 {
    if tiles.is_empty() {
        return 0;
    }
    let mut hist = [0u32; 256];
    for t in tiles {
        hist[t.elevation as usize] += 1;
    }
    let target = (tiles.len() as f64 * f64::from(sea_fraction.clamp(0.0, 1.0))) as u64;
    let mut acc: u64 = 0;
    for (level, &count) in hist.iter().enumerate() {
        acc += u64::from(count);
        if acc >= target {
            return level as u8;
        }
    }
    255
}

fn assign_biomes(tiles: &mut [Tile], sea_level: u8) {
    for t in tiles.iter_mut() {
        t.biome = pick_biome(t.elevation, t.moisture, t.temperature, sea_level);
    }
}

fn sample_octaves(n: &Perlin, x: f64, y: f64, octaves: u32) -> f64 {
    let mut amp = 1.0_f64;
    let mut freq = 1.0_f64;
    let mut sum = 0.0_f64;
    let mut norm = 0.0_f64;
    for _ in 0..octaves {
        sum += amp * n.get([x * freq, y * freq]);
        norm += amp;
        amp *= 0.5;
        freq *= 2.0;
    }
    // Perlin returns roughly [-1, 1]; remap to [0, 1].
    let v = sum / norm.max(f64::EPSILON);
    (v * 0.5 + 0.5).clamp(0.0, 1.0)
}

fn unit_to_u8(v: f64) -> u8 {
    let scaled = (v * 255.0).round();
    if scaled <= 0.0 {
        0
    } else if scaled >= 255.0 {
        255
    } else {
        scaled as u8
    }
}

fn pick_biome(elev: u8, moist: u8, temp: u8, sea_level: u8) -> Biome {
    if elev < sea_level.saturating_sub(16) {
        return Biome::Ocean;
    }
    if elev < sea_level {
        return Biome::Coast;
    }
    if elev > 220 {
        return Biome::Mountain;
    }
    if elev > 180 {
        return Biome::Hills;
    }
    if temp < 60 {
        return Biome::Tundra;
    }
    if moist < 80 {
        return Biome::Desert;
    }
    if moist > 170 {
        return Biome::Forest;
    }
    Biome::Plains
}

fn sprinkle_rivers(tiles: &mut [Tile], dims: WorldDims) {
    // Cheap & deterministic: pick the highest non-mountain, non-ocean tile in
    // each NxN cell and trace a single river path downhill until it hits water
    // or runs out of slope.
    const CELL: i32 = 24;
    let (w, h) = (dims.w as i32, dims.h as i32);
    for cy in 0..(h / CELL) {
        for cx in 0..(w / CELL) {
            let mut best: Option<(i32, i32, u8)> = None;
            for dy in 0..CELL {
                for dx in 0..CELL {
                    let x = cx * CELL + dx;
                    let y = cy * CELL + dy;
                    let i = (y as usize) * dims.w as usize + x as usize;
                    let t = tiles[i];
                    if matches!(t.biome, Biome::Ocean | Biome::Mountain) {
                        continue;
                    }
                    if best.is_none_or(|b| t.elevation > b.2) {
                        best = Some((x, y, t.elevation));
                    }
                }
            }
            if let Some((mut x, mut y, _)) = best {
                for _ in 0..(CELL * 4) {
                    let i = (y as usize) * dims.w as usize + x as usize;
                    let t = &mut tiles[i];
                    if matches!(t.biome, Biome::Ocean | Biome::Coast) {
                        break;
                    }
                    t.set_tag(tile_tags::RIVER);
                    // Step to lowest neighbour.
                    let mut nx = x;
                    let mut ny = y;
                    let mut lowest = t.elevation;
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let xx = x + dx;
                        let yy = y + dy;
                        if xx < 0 || yy < 0 || xx >= w || yy >= h {
                            continue;
                        }
                        let j = (yy as usize) * dims.w as usize + xx as usize;
                        if tiles[j].elevation < lowest {
                            lowest = tiles[j].elevation;
                            nx = xx;
                            ny = yy;
                        }
                    }
                    if (nx, ny) == (x, y) {
                        break;
                    }
                    x = nx;
                    y = ny;
                }
            }
        }
    }
}

fn sprinkle_ruins(tiles: &mut [Tile], dims: WorldDims, rng: &mut DetRng, density: f32) {
    if density <= 0.0 {
        return;
    }
    let n = (dims.area() as f32 * density).round() as u32;
    for _ in 0..n {
        let x = rng.gen_range_u32(dims.w) as i32;
        let y = rng.gen_range_u32(dims.h) as i32;
        if let Some(i) = dims.idx(x, y) {
            if tiles[i].is_settleable() {
                tiles[i].set_tag(tile_tags::RUIN);
            }
        }
    }
}

fn sprinkle_zones(tiles: &mut [Tile], dims: WorldDims, rng: &mut DetRng, count: u32) {
    for _ in 0..count {
        let x = rng.gen_range_u32(dims.w) as i32;
        let y = rng.gen_range_u32(dims.h) as i32;
        if let Some(i) = dims.idx(x, y) {
            if !matches!(tiles[i].biome, Biome::Ocean) {
                tiles[i].set_tag(tile_tags::ZONE);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SimConfig;

    #[test]
    fn deterministic_for_same_seed() {
        let cfg = SimConfig {
            seed: 1234,
            dims: WorldDims { w: 64, h: 64 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut a = World::new(&cfg).unwrap();
        let mut b = World::new(&cfg).unwrap();
        generate(&mut a, &WorldGenParams::default()).unwrap();
        generate(&mut b, &WorldGenParams::default()).unwrap();
        assert_eq!(a.tiles, b.tiles);
    }

    #[test]
    fn different_seed_different_world() {
        let mut cfg = SimConfig {
            seed: 1,
            dims: WorldDims { w: 64, h: 64 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut a = World::new(&cfg).unwrap();
        cfg.seed = 2;
        let mut b = World::new(&cfg).unwrap();
        generate(&mut a, &WorldGenParams::default()).unwrap();
        generate(&mut b, &WorldGenParams::default()).unwrap();
        assert_ne!(a.tiles, b.tiles);
    }

    #[test]
    fn biomes_have_oceans_and_land() {
        let cfg = SimConfig {
            seed: 7,
            dims: WorldDims { w: 64, h: 64 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        };
        let mut w = World::new(&cfg).unwrap();
        generate(&mut w, &WorldGenParams::default()).unwrap();
        let oceans = w.tiles.iter().filter(|t| t.biome == Biome::Ocean).count();
        let land = w.tiles.iter().filter(|t| t.biome != Biome::Ocean).count();
        assert!(oceans > 0, "expected some oceans");
        assert!(land > 0, "expected some land");
    }
}
