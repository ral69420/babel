//! `babel_lang` — procedural language generation.
//!
//! No LLM, no AI. We generate words and names from hand-authored
//! **phoneme sets** plus a small Markov chain seeded by an example word list.
//! Each phoneme set is a TOML file in `content/phoneme_sets/*.toml`.
//!
//! ## Pipeline
//!
//! 1. Load a [`PhonemeSet`] (consonants, vowels, syllable shapes, banned
//!    sequences).
//! 2. Build a [`Markov`] chain from the example words and the syllable shape
//!    rules.
//! 3. Generate words with [`Language::word`] / names with [`Language::name`].
//!
//! All generation flows through [`babel_sim::DetRng`], so for a given seed +
//! phoneme set the output is byte-identical.

#![deny(missing_docs)]

use serde::{Deserialize, Serialize};

use babel_sim::DetRng;

/// Built-in culture identifiers — one per phoneme set in
/// `content/phoneme_sets/`. Order is **stable** and used as `language_id`
/// on `Civilization`. Adding a new culture appends; never reorder.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u32)]
pub enum Culture {
    /// Sand-stone, sibilant, arid.
    Kheltari = 0,
    /// River-island, vowel-heavy.
    Orunmare = 1,
    /// Stone-mountain, hard.
    Dvarni = 2,
    /// Forest-twilight, lateral-rich.
    Eluran = 3,
    /// Desert-trader, guttural.
    Qarasil = 4,
    /// Snow-tundra, palatalised.
    Ningaer = 5,
    /// River-temple, retroflex.
    Sankhara = 6,
}

impl Culture {
    /// Every culture in stable order. Index matches `language_id`.
    pub const ALL: [Culture; 7] = [
        Self::Kheltari,
        Self::Orunmare,
        Self::Dvarni,
        Self::Eluran,
        Self::Qarasil,
        Self::Ningaer,
        Self::Sankhara,
    ];

    /// Numeric id (matches `Civilization::language_id`).
    #[must_use]
    pub fn id(self) -> u32 {
        self as u32
    }

    /// Decode from numeric id. Returns `None` if out of range.
    #[must_use]
    pub fn from_id(id: u32) -> Option<Self> {
        Self::ALL.get(id as usize).copied()
    }

    /// Lower-case slug (matches the phoneme-set TOML filename).
    #[must_use]
    pub fn slug(self) -> &'static str {
        match self {
            Self::Kheltari => "kheltari",
            Self::Orunmare => "orunmare",
            Self::Dvarni => "dvarni",
            Self::Eluran => "eluran",
            Self::Qarasil => "qarasil",
            Self::Ningaer => "ningaer",
            Self::Sankhara => "sankhara",
        }
    }
}

/// Phoneme-set TOML embedded at compile time so `babel_lang` has no runtime
/// I/O dependency. Order matches [`Culture::ALL`].
const KHELTARI_TOML: &str = include_str!("../../../../content/phoneme_sets/kheltari.toml");
const ORUNMARE_TOML: &str = include_str!("../../../../content/phoneme_sets/orunmare.toml");
const DVARNI_TOML: &str = include_str!("../../../../content/phoneme_sets/dvarni.toml");
const ELURAN_TOML: &str = include_str!("../../../../content/phoneme_sets/eluran.toml");
const QARASIL_TOML: &str = include_str!("../../../../content/phoneme_sets/qarasil.toml");
const NINGAER_TOML: &str = include_str!("../../../../content/phoneme_sets/ningaer.toml");
const SANKHARA_TOML: &str = include_str!("../../../../content/phoneme_sets/sankhara.toml");

/// Build all seven default languages, in [`Culture::ALL`] order. Panics if
/// the embedded TOML is malformed — that is a build-time bug, not a runtime
/// one.
#[must_use]
pub fn default_languages() -> Vec<Language> {
    let toml_for = |c: Culture| match c {
        Culture::Kheltari => KHELTARI_TOML,
        Culture::Orunmare => ORUNMARE_TOML,
        Culture::Dvarni => DVARNI_TOML,
        Culture::Eluran => ELURAN_TOML,
        Culture::Qarasil => QARASIL_TOML,
        Culture::Ningaer => NINGAER_TOML,
        Culture::Sankhara => SANKHARA_TOML,
    };
    Culture::ALL
        .iter()
        .map(|c| {
            let phon =
                PhonemeSet::from_toml(toml_for(*c)).expect("embedded phoneme set must parse");
            Language::build(phon)
        })
        .collect()
}

/// Hand-authored phoneme set. Loaded from TOML.
///
/// ```toml
/// name = "kheltari"
/// consonants = ["k", "th", "l", "r", "n", "v", "z"]
/// vowels = ["a", "e", "i", "o", "u", "ai"]
/// syllables = ["CV", "CVC", "VC"]
/// banned = ["thth", "rr"]
/// example_words = ["kheltar", "linov", "azumai"]
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhonemeSet {
    /// Internal name.
    pub name: String,
    /// List of consonant graphemes (may be multi-char digraphs).
    pub consonants: Vec<String>,
    /// List of vowel graphemes.
    pub vowels: Vec<String>,
    /// Allowed syllable shapes. `C` = consonant, `V` = vowel.
    pub syllables: Vec<String>,
    /// Forbidden substrings — generation rejects words containing them.
    #[serde(default)]
    pub banned: Vec<String>,
    /// Example words — used to seed bigram weights.
    #[serde(default)]
    pub example_words: Vec<String>,
}

/// Parse errors from `PhonemeSet::from_toml`.
#[derive(Debug, thiserror::Error)]
pub enum LangError {
    /// TOML parse failure.
    #[error("toml parse: {0}")]
    Toml(#[from] toml::de::Error),
    /// Set is structurally invalid.
    #[error("invalid phoneme set: {0}")]
    Invalid(&'static str),
}

impl PhonemeSet {
    /// Parse from TOML.
    pub fn from_toml(s: &str) -> Result<Self, LangError> {
        let p: PhonemeSet = toml::from_str(s)?;
        p.validate()?;
        Ok(p)
    }

    /// Run sanity checks.
    pub fn validate(&self) -> Result<(), LangError> {
        if self.consonants.is_empty() {
            return Err(LangError::Invalid("no consonants"));
        }
        if self.vowels.is_empty() {
            return Err(LangError::Invalid("no vowels"));
        }
        if self.syllables.is_empty() {
            return Err(LangError::Invalid("no syllables"));
        }
        for s in &self.syllables {
            for c in s.chars() {
                if c != 'C' && c != 'V' {
                    return Err(LangError::Invalid("syllable must contain only C/V"));
                }
            }
        }
        Ok(())
    }
}

/// A built language ready to generate words.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Language {
    /// Source phoneme set.
    pub phonemes: PhonemeSet,
    /// Bigram weights — `next_consonant_after[i]` is a weight slice.
    bigram_c: Vec<Vec<u32>>,
    bigram_v: Vec<Vec<u32>>,
}

impl Language {
    /// Build a language from a phoneme set + example words.
    #[must_use]
    pub fn build(phonemes: PhonemeSet) -> Self {
        let nc = phonemes.consonants.len();
        let nv = phonemes.vowels.len();
        let mut bigram_c = vec![vec![1u32; nc]; nc + 1]; // +1 for "start"
        let mut bigram_v = vec![vec![1u32; nv]; nv + 1];
        // Train on example words.
        for word in &phonemes.example_words {
            train_bigrams(word, &phonemes, &mut bigram_c, &mut bigram_v);
        }
        Self {
            phonemes,
            bigram_c,
            bigram_v,
        }
    }

    /// Generate one word of `syllables` syllables.
    ///
    /// Falls back to the first allowed syllable if the configured shape pool
    /// is empty (validated by `PhonemeSet::validate`).
    pub fn word(&self, rng: &mut DetRng, syllables: u8) -> String {
        // Reject loops a bounded number of times to avoid infinite loops on
        // pathological banned-substring lists.
        for _ in 0..16 {
            let candidate = self.gen_once(rng, syllables);
            if !self
                .phonemes
                .banned
                .iter()
                .any(|b| candidate.contains(b.as_str()))
            {
                return candidate;
            }
        }
        // Last-ditch: return the candidate even if banned matches; this
        // guarantees the function always returns a word.
        self.gen_once(rng, syllables)
    }

    /// Generate a personal name (1–3 syllables, capitalised).
    pub fn name(&self, rng: &mut DetRng) -> String {
        let n = 1 + rng.gen_range_u32(3) as u8;
        let w = self.word(rng, n);
        // Capitalise first character, preserving multi-byte UTF-8.
        let mut chars = w.chars();
        match chars.next() {
            None => String::new(),
            Some(c) => c.to_uppercase().chain(chars).collect(),
        }
    }

    /// Generate a city name (2–4 syllables).
    pub fn city_name(&self, rng: &mut DetRng) -> String {
        let n = 2 + rng.gen_range_u32(3) as u8;
        let w = self.word(rng, n);
        let mut chars = w.chars();
        match chars.next() {
            None => String::new(),
            Some(c) => c.to_uppercase().chain(chars).collect(),
        }
    }

    fn gen_once(&self, rng: &mut DetRng, syllables: u8) -> String {
        let mut out = String::with_capacity(usize::from(syllables) * 3);
        let mut last_c: Option<usize> = None;
        let mut last_v: Option<usize> = None;
        for _ in 0..syllables {
            let shape = rng
                .pick(&self.phonemes.syllables)
                .expect("validated non-empty");
            for ch in shape.chars() {
                match ch {
                    'C' => {
                        let idx = pick_weighted(rng, last_c, &self.bigram_c);
                        out.push_str(&self.phonemes.consonants[idx]);
                        last_c = Some(idx);
                    }
                    'V' => {
                        let idx = pick_weighted(rng, last_v, &self.bigram_v);
                        out.push_str(&self.phonemes.vowels[idx]);
                        last_v = Some(idx);
                    }
                    _ => unreachable!("validated"),
                }
            }
        }
        out
    }
}

fn pick_weighted(rng: &mut DetRng, prev: Option<usize>, table: &[Vec<u32>]) -> usize {
    // Row index: prev or last row (the "start" / no-prev entry).
    let row = prev.unwrap_or(table.len() - 1);
    let row = &table[row];
    let total: u64 = row.iter().map(|&v| u64::from(v)).sum();
    if total == 0 {
        return 0;
    }
    let mut t = u64::from(rng.gen_range_u32((total as u32).max(1)));
    for (i, &v) in row.iter().enumerate() {
        let v = u64::from(v);
        if t < v {
            return i;
        }
        t -= v;
    }
    row.len() - 1
}

fn train_bigrams(word: &str, p: &PhonemeSet, bigram_c: &mut [Vec<u32>], bigram_v: &mut [Vec<u32>]) {
    // Greedy left-to-right tokenisation against the phoneme list.
    let mut last_c: Option<usize> = None;
    let mut last_v: Option<usize> = None;
    let mut s = word;
    while !s.is_empty() {
        if let Some((idx, len)) = best_match(s, &p.consonants) {
            let prev = last_c.unwrap_or(p.consonants.len());
            bigram_c[prev][idx] += 4;
            last_c = Some(idx);
            s = &s[len..];
        } else if let Some((idx, len)) = best_match(s, &p.vowels) {
            let prev = last_v.unwrap_or(p.vowels.len());
            bigram_v[prev][idx] += 4;
            last_v = Some(idx);
            s = &s[len..];
        } else {
            // Skip an unknown char (e.g. apostrophe in example words).
            let next = s.char_indices().nth(1).map(|(i, _)| i).unwrap_or(s.len());
            s = &s[next..];
        }
    }
}

fn best_match(s: &str, pool: &[String]) -> Option<(usize, usize)> {
    let mut best: Option<(usize, usize)> = None;
    for (i, p) in pool.iter().enumerate() {
        if s.starts_with(p) && best.is_none_or(|b| p.len() > b.1) {
            best = Some((i, p.len()));
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> PhonemeSet {
        PhonemeSet {
            name: "test".into(),
            consonants: vec!["k".into(), "l".into(), "n".into(), "r".into()],
            vowels: vec!["a".into(), "e".into(), "i".into()],
            syllables: vec!["CV".into(), "CVC".into()],
            banned: vec!["rr".into()],
            example_words: vec!["kanela".into(), "lirin".into()],
        }
    }

    #[test]
    fn validate_rejects_empty() {
        let mut p = fixture();
        p.consonants.clear();
        assert!(p.validate().is_err());
    }

    #[test]
    fn deterministic_word() {
        let lang = Language::build(fixture());
        let mut a = DetRng::from_seed(42);
        let mut b = DetRng::from_seed(42);
        for _ in 0..32 {
            assert_eq!(lang.word(&mut a, 2), lang.word(&mut b, 2));
        }
    }

    #[test]
    fn name_starts_uppercase() {
        let lang = Language::build(fixture());
        let mut rng = DetRng::from_seed(1);
        for _ in 0..16 {
            let n = lang.name(&mut rng);
            let first = n.chars().next().unwrap();
            assert!(first.is_uppercase(), "name {n:?} did not start uppercase");
        }
    }

    #[test]
    fn no_banned_substrings() {
        let lang = Language::build(fixture());
        let mut rng = DetRng::from_seed(99);
        let bad = "rr";
        for _ in 0..256 {
            let w = lang.word(&mut rng, 3);
            assert!(!w.contains(bad), "got banned substring in {w:?}");
        }
    }

    #[test]
    fn default_languages_loads_all_seven() {
        let langs = default_languages();
        assert_eq!(langs.len(), Culture::ALL.len());
        // Every language must be able to produce a non-empty name.
        for (i, lang) in langs.iter().enumerate() {
            let mut rng = DetRng::from_seed(i as u64);
            let n = lang.name(&mut rng);
            assert!(
                !n.is_empty(),
                "{} produced empty name",
                Culture::ALL[i].slug()
            );
        }
    }

    #[test]
    fn culture_id_roundtrip() {
        for c in Culture::ALL {
            assert_eq!(Culture::from_id(c.id()), Some(c));
        }
        assert_eq!(Culture::from_id(99), None);
    }
}
