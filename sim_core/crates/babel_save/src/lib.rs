//! `babel_save` — versioned binary save/load with migration support.
//!
//! ## Why custom?
//!
//! - JSON is too large + slow for 256×256 maps with thousands of NPCs.
//! - bincode + zstd round-trips a quarter-million tiles in ~30 KB.
//! - Versioning is mandatory: any change to a serialized struct bumps
//!   [`babel_sim::world::SIM_VERSION`] and adds a migration step here.
//!
//! ## File layout
//!
//! ```text
//! [magic 8 bytes "BABELSAV"]
//! [u32 file_version]      — bump on file-format change (header layout)
//! [u32 sim_version]       — copy of SIM_VERSION at write time
//! [u32 zstd_payload_len]
//! [bytes zstd_payload]    — bincode of [`World`]
//! ```
//!
//! ## Atomicity
//!
//! Saves write to `<path>.tmp`, fsync, then rename — never overwrite the
//! existing save in place.

#![deny(missing_docs)]

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use babel_sim::World;

/// Magic header.
pub const MAGIC: [u8; 8] = *b"BABELSAV";
/// Save-file format version (header layout).
pub const FILE_VERSION: u32 = 1;

/// Errors raised by the save subsystem.
#[derive(Debug, thiserror::Error)]
pub enum SaveError {
    /// I/O failure while reading or writing the save file.
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    /// Bincode (en|de)coding failure.
    #[error("bincode: {0}")]
    Bincode(#[from] bincode::Error),
    /// Magic header mismatch — file is not a Babel save (or is truncated).
    #[error("not a babel save (bad magic)")]
    BadMagic,
    /// The file format version is unsupported.
    #[error("unsupported file_version: {0}")]
    UnsupportedFileVersion(u32),
    /// The sim version is too new for this binary to load.
    #[error("save sim_version {0} is newer than runtime sim_version {1}")]
    NewerSim(u32, u32),
    /// No migration registered for this sim_version.
    #[error("no migration path from sim_version {0} to {1}")]
    NoMigration(u32, u32),
}

/// Save a world atomically to `path`.
pub fn save(world: &World, path: impl AsRef<Path>) -> Result<(), SaveError> {
    let path = path.as_ref();
    let tmp = tmp_path(path);
    let payload = bincode::serialize(world)?;
    let compressed = zstd::stream::encode_all(payload.as_slice(), 8)?;
    {
        let mut f = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&tmp)?;
        f.write_all(&MAGIC)?;
        f.write_all(&FILE_VERSION.to_le_bytes())?;
        f.write_all(&world.sim_version.to_le_bytes())?;
        let len =
            u32::try_from(compressed.len()).map_err(|_| std::io::Error::other("save too large"))?;
        f.write_all(&len.to_le_bytes())?;
        f.write_all(&compressed)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

fn tmp_path(p: &Path) -> PathBuf {
    let mut s = p.as_os_str().to_owned();
    s.push(".tmp");
    PathBuf::from(s)
}

/// Load a world from `path`, applying any migrations needed.
pub fn load(path: impl AsRef<Path>) -> Result<World, SaveError> {
    let mut f = File::open(path)?;
    let mut magic = [0u8; 8];
    f.read_exact(&mut magic)?;
    if magic != MAGIC {
        return Err(SaveError::BadMagic);
    }
    let mut buf4 = [0u8; 4];
    f.read_exact(&mut buf4)?;
    let file_version = u32::from_le_bytes(buf4);
    if file_version != FILE_VERSION {
        return Err(SaveError::UnsupportedFileVersion(file_version));
    }
    f.read_exact(&mut buf4)?;
    let sim_version = u32::from_le_bytes(buf4);
    f.read_exact(&mut buf4)?;
    let payload_len = u32::from_le_bytes(buf4) as usize;
    let mut compressed = vec![0u8; payload_len];
    f.read_exact(&mut compressed)?;
    let raw = zstd::stream::decode_all(compressed.as_slice())?;

    let world: World = if sim_version == babel_sim::world::SIM_VERSION {
        bincode::deserialize(&raw)?
    } else if sim_version > babel_sim::world::SIM_VERSION {
        return Err(SaveError::NewerSim(
            sim_version,
            babel_sim::world::SIM_VERSION,
        ));
    } else {
        migrate(sim_version, &raw)?
    };
    Ok(world)
}

/// Migration registry. Add a `match` arm here every time you bump
/// [`babel_sim::world::SIM_VERSION`].
fn migrate(from: u32, _raw: &[u8]) -> Result<World, SaveError> {
    // No older versions yet. The first migration to write will look like:
    //
    // 0 => {
    //     let v0: WorldV0 = bincode::deserialize(_raw)?;
    //     Ok(v0.into())
    // }
    Err(SaveError::NoMigration(from, babel_sim::world::SIM_VERSION))
}

#[cfg(test)]
mod tests {
    use super::*;
    use babel_sim::{SimConfig, World, WorldDims};

    fn cfg() -> SimConfig {
        SimConfig {
            seed: 0xCAFE,
            dims: WorldDims { w: 16, h: 16 },
            starting_civs: 0,
            starting_npcs_per_civ: 0,
        }
    }

    #[test]
    fn roundtrip_in_tempdir() {
        let dir = tempdir();
        let path = dir.join("save.bbl");
        let mut world = World::new(&cfg()).unwrap();
        babel_sim::worldgen::generate(&mut world, &Default::default()).unwrap();
        save(&world, &path).unwrap();
        let loaded = load(&path).unwrap();
        assert_eq!(world.tiles, loaded.tiles);
        assert_eq!(world.dims, loaded.dims);
        assert_eq!(world.sim_version, loaded.sim_version);
    }

    #[test]
    fn bad_magic_rejected() {
        let dir = tempdir();
        let path = dir.join("bad.bbl");
        std::fs::write(&path, b"not_a_save_file").unwrap();
        match load(&path) {
            Err(SaveError::BadMagic) => {}
            other => panic!("expected BadMagic, got {other:?}"),
        }
    }

    fn tempdir() -> std::path::PathBuf {
        let base = std::env::temp_dir();
        let mut p = base;
        p.push(format!("babel_save_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }
}
