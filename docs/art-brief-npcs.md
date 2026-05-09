# NPC quickstart — 28 idle-спрайтов

Цель этого документа: ты сгенерируешь **28 одиночных спрайтов** (по одному кадру каждый), бросишь в нужные папки — я их подхвачу, прогоню через линт, и покажу в Godot. Ничего больше пока не делай — анимации, ходьба, бой добавим позже.

## 0. Что вообще генерируем

7 культур × 4 архетипа = **28 PNG-файлов**.
Один спрайт = один персонаж стоит, лицом примерно к камере (3/4-поворот, ~75°), без анимации, без тени, прозрачный фон.

| культура | палитра-якорь | образ |
|---|---|---|
| **kheltari** | A-серия + D-серия (серо-синий + бежевый) | горные пастухи в шерсти, копчёная кожа, копперовые амулеты |
| **orunmare** | A6/A7 + E3/E4 (охра + закатный жжёный) | саваннские сын-дольщики, льняные обмотки, латунь |
| **dvarni** | B1/B2 + D1 + G3 (тёмный мох + железо) | северные лесовики в коже и мехе |
| **eluran** | C3/C4 + D4 + G1 (бирюза + жемчуг) | прибрежные лагунщики, отбелённый лён |
| **qarasil** | A6/A7 + F1 (песок + индиго) | пустынные кочевники в обмотках, лица закрыты |
| **ningaer** | B3/B4 + A5 (жадеит + тростник) | дельтовый рисосей, конические соломенные шляпы |
| **sankhara** | F1/F2/F3 + G2 (фиолет + пепел) | высокогорные аскеты, бритые головы или пучки |

Архетипы (одинаковые для всех 7):
- **commoner** — простая рабочая одежда, в руках ничего или корзинка/миска
- **elder** — длинный халат, посох, седые волосы/борода
- **warrior** — броня, меч/копьё **в ножнах** (не вытаскивать), щит за спиной ок
- **priest** — ритуальный халат, амулет/сигил культуры, головной убор/капюшон

## 1. Чем генерить (выбери одно)

| вариант | плюс | минус |
|---|---|---|
| **ChatGPT-4o (картинка)** — встроенная в чат | бесплатно, копи-паст | пропорции скачут, требует `Aseprite` для приведения к 24×32 |
| **Midjourney v6** — `/imagine` | стабильный стиль | платно, через Discord |
| **SDXL + LoRA `nerijs/pixel-art-xl`** на ComfyUI / Forge | бесплатно локально, лучшее качество | нужно ставить |
| **Aseprite вручную** — открыть `babel_v1.gpl`, нарисовать 24×32 | 100% on-palette сразу | долго |

**Рекомендую SDXL + pixel-art-xl LoRA** (1024×1024, потом downscale в Aseprite). Если лень — ChatGPT-4o, потом всё равно через Aseprite.

## 2. Output spec — обязательно

- **Файл:** PNG, прозрачный фон
- **Размер на выходе:** **24×32 px** (если AI выдал больше — downscale в Aseprite через `Sprite → Sprite Size → Resample: Nearest`)
- **Палитра:** только из `godot_project/assets/palette/babel_v1.gpl`. В Aseprite: `Sprite → Color Mode → Indexed → Use a custom palette → Open palette → babel_v1.gpl`. Все «лишние» пиксели маппятся на ближайший цвет.
- **Поза:** стоит, фронтальный 3/4-поворот, обе ноги видны, обе руки видны, без оружия наготове (только в ножнах для warrior)
- **Без обводки** — силуэт читается тоном, не контуром
- **Без тени** — тень рисуем уже в движке
- **Имя файла:** `{archetype}_idle.png` (например `commoner_idle.png`)

## 3. Master prompt prefix (вставлять перед каждой вариацией)

```
top-down 3/4 RPG character sprite, hand-painted pixel art, 24x32 pixels,
"Sea of Stars" + "Songs of Syx" + "Eastward" style, warm desaturated
palette, no outline, soft AA shading, transparent background, single
character standing idle, facing camera with slight 3/4 turn (75 degree),
full body visible head to feet, no shadow, clean readable silhouette,
indexed colors, weapons sheathed if any
```

**Negative prompt** (для SDXL/Forge/etc.):
```
blurry, photorealistic, 3d render, anime face, modern clothes, hoodie,
sneakers, sunglasses, gun, multiple characters, isometric, pure
top-down, pure side view, gradient background, white background,
heavy black outline, oversaturated, neon, low contrast soup
```

**SDXL settings:** 1024×1024, steps 30, CFG 5–6, sampler `DPM++ 2M Karras`, LoRA `pixel-art-xl` strength 1.0, seed зафиксируй для серии (чтобы лица и пропорции совпадали внутри одной культуры).

## 4. 28 заполненных промптов

Формат: вставляешь master prefix → запятая → строку из таблицы.

### kheltari (горные пастухи, серо-синий + бежевый)
- **commoner** — `kheltari mountain herder, slate grey-blue wool tunic over bone-cream undershirt, plain leather belt and boots, calloused hands holding small woven basket, cropped dark hair, stoic weathered face, copper buckle`
- **elder** — `kheltari mountain elder, long slate-blue wool robe with bone-cream embroidered hem, gnarled walking staff, full grey beard, deep wrinkles, copper amulet of carved mountain stone, hood down`
- **warrior** — `kheltari mountain warrior, slate-blue ringmail over wool gambeson, round wooden shield slung on back, sheathed straight sword at hip, scarred jaw, short helmet of riveted iron, hands at sides`
- **priest** — `kheltari mountain priest, pale grey hooded robe with bone-cream stone-circle motif on chest, copper sun-disk amulet, no beard, eyes lowered in calm prayer, palms open`

### orunmare (саваннские сын-дольщики, охра + закатный жжёный)
- **commoner** — `orunmare savannah villager, ochre linen wrap with sunset-orange sash, brass anklets, dark warm skin, long braided hair, carrying clay water gourd, bare feet, calm expression`
- **elder** — `orunmare savannah elder, deep-ochre layered linen robe, brass armbands and sun-disk pendant, long staff topped with carved acacia bird, white hair in tight braids, dark warm skin, kind crinkled eyes`
- **warrior** — `orunmare savannah warrior, ochre leather cuirass with brass studs, sunset-orange shoulder cape, sheathed curved sword at hip, oval hide shield slung, dark warm skin, braided warrior locks, painted ochre marks under eyes`
- **priest** — `orunmare savannah priest, white-and-ochre linen robe with sunset-orange brass-disk collar, head wrapped in cream cloth, dark warm skin, holding small brass bowl, serene face`

### dvarni (северные лесовики, тёмный мох + железо)
- **commoner** — `dvarni forest peasant, dark mossy-green wool tunic, brown fur-trimmed vest, iron belt buckle, carrying axe handle (no axe head, just shaft), pale weathered skin, dark untidy hair, plain leather boots`
- **elder** — `dvarni forest elder, long dark-green wool robe, heavy wolfskin cloak across shoulders, iron-tipped staff, long iron-grey beard, pale weathered face, small carved-bone amulet`
- **warrior** — `dvarni forest warrior, layered dark-green leather and iron lamellar, wolfskin shoulder mantle, sheathed bearded axe at hip, round iron-rimmed wooden shield slung, pale skin, dark braided beard`
- **priest** — `dvarni forest priest, ash-grey hooded robe with dark-green tree-rune embroidery, antler-tip pendant, pale skin, eyes shadowed by hood, holding small bundle of birch twigs`

### eluran (прибрежные лагунщики, бирюза + жемчуг)
- **commoner** — `eluran coastal villager, pale-teal linen tunic, bleached cream sash, sun-kissed skin, salt-bleached hair, holding fishing net rolled up, bare feet, gentle smile`
- **elder** — `eluran coastal elder, layered teal-and-cream linen robe, mother-of-pearl pendant, long-thin coral staff, white hair tied back, sun-kissed weathered skin, calm tired eyes`
- **warrior** — `eluran coastal warrior, pale-teal leather scale armor with cream cloth wrap, sheathed thin curved blade at hip, light wicker shield slung, sun-kissed skin, hair pulled back, no helmet`
- **priest** — `eluran coastal priest, bleached cream robe with teal embroidered wave pattern, pearl-string circlet, sun-kissed skin, holding small shell bowl with sea-water, eyes closed in prayer`

### qarasil (пустынные кочевники, песок + индиго)
- **commoner** — `qarasil desert nomad, sand-bone layered linen wraps, deep indigo veil covering lower face and head, tan skin, only dark eyes visible, holding rolled travel mat, sandals`
- **elder** — `qarasil desert elder, full sand-bone robe and indigo head-wrap, indigo half-veil lowered to chin, white beard partially visible, deep tan weathered skin, long carved walking staff with brass cap`
- **warrior** — `qarasil desert warrior, sand-bone layered wraps over indigo undertunic, indigo veil up covering lower face, sheathed curved scimitar at hip, small round metal shield slung, leather bracers, dark fierce eyes`
- **priest** — `qarasil desert priest, deep indigo hooded robe with sand-bone stitched constellation pattern, brass star-pendant, lower face veiled in indigo, holding tiny brass mirror, calm steady eyes`

### ningaer (дельтовый рисосей, жадеит + тростник)
- **commoner** — `ningaer river farmer, jade-green linen tunic with reed-tan trousers rolled up to knees, conical straw hat, warm tan skin, holding wooden rice paddle, calm bright face, bare feet`
- **elder** — `ningaer river elder, long jade-green silk robe with reed-tan sash, wide conical straw hat, long carved bamboo staff, long white wispy beard, warm tan skin, kind narrow eyes`
- **warrior** — `ningaer river warrior, jade-green lacquered scale over reed-tan padded tunic, conical iron-rimmed straw hat, sheathed straight thin sword at hip, slim build, warm tan skin, calm focused eyes`
- **priest** — `ningaer river priest, soft jade-green silk robe with reed-tan stole, head shaved, warm tan skin, holding bundle of fragrant reeds, serene closed-eye expression`

### sankhara (высокогорные аскеты, фиолет + пепел)
- **commoner** — `sankhara plateau ascetic worker, ash-grey rough-spun robe with dusty-violet sash, shaved head, fair skin with pinkish weathering, simple wooden bowl in hands, bare feet, peaceful neutral face`
- **elder** — `sankhara plateau elder, layered dusty-violet and ash-grey robes, heavy wooden prayer beads around neck, shaved head with thin white topknot, fair lined skin, holding tall plain staff with violet ribbon, kind tired eyes`
- **warrior** — `sankhara plateau warden, ash-grey padded robe under dusty-violet cuirass, sheathed straight monk sword at hip, no helmet, shaved head with thin warrior topknot, fair skin, calm watchful eyes, prayer beads around left wrist`
- **priest** — `sankhara plateau priest, deep dusty-violet ceremonial robe with magic-violet embroidered sigils glowing softly, ash-grey under-robe, shaved head, fair skin, holding small bronze bell, eyes half-closed in trance`

## 5. Куда класть (точные пути)

```
godot_project/assets/npcs/kheltari/commoner_idle.png
godot_project/assets/npcs/kheltari/elder_idle.png
godot_project/assets/npcs/kheltari/warrior_idle.png
godot_project/assets/npcs/kheltari/priest_idle.png
godot_project/assets/npcs/orunmare/commoner_idle.png
godot_project/assets/npcs/orunmare/elder_idle.png
godot_project/assets/npcs/orunmare/warrior_idle.png
godot_project/assets/npcs/orunmare/priest_idle.png
godot_project/assets/npcs/dvarni/commoner_idle.png
godot_project/assets/npcs/dvarni/elder_idle.png
godot_project/assets/npcs/dvarni/warrior_idle.png
godot_project/assets/npcs/dvarni/priest_idle.png
godot_project/assets/npcs/eluran/commoner_idle.png
godot_project/assets/npcs/eluran/elder_idle.png
godot_project/assets/npcs/eluran/warrior_idle.png
godot_project/assets/npcs/eluran/priest_idle.png
godot_project/assets/npcs/qarasil/commoner_idle.png
godot_project/assets/npcs/qarasil/elder_idle.png
godot_project/assets/npcs/qarasil/warrior_idle.png
godot_project/assets/npcs/qarasil/priest_idle.png
godot_project/assets/npcs/ningaer/commoner_idle.png
godot_project/assets/npcs/ningaer/elder_idle.png
godot_project/assets/npcs/ningaer/warrior_idle.png
godot_project/assets/npcs/ningaer/priest_idle.png
godot_project/assets/npcs/sankhara/commoner_idle.png
godot_project/assets/npcs/sankhara/elder_idle.png
godot_project/assets/npcs/sankhara/warrior_idle.png
godot_project/assets/npcs/sankhara/priest_idle.png
```

Папки уже созданы — просто бросай файлы.

## 6. Перед тем как сказать «готово»

1. **Squint test:** прищурься на тамбнейлы — ты должен по силуэту угадать культуру и роль (kheltari vs eluran должны выглядеть разно; commoner vs warrior — тем более).
2. **Размер:** все файлы **ровно 24×32** (`identify -format '%wx%h\n' *.png` или просто свойства файла).
3. **Прозрачный фон:** никакой белой/чёрной заливки за персонажем.
4. **Палитра:** в Aseprite `Sprite → Color Mode → Indexed → babel_v1.gpl`. Если после индексации картинка изменилась радикально — значит цвета вне палитры, перегенерь / поправь.
5. **Имена:** ровно как в списке выше (английскими, lowercase, `_idle.png`).

## 7. Что делать, если AI выдаёт мусор

- Не получается анатомия → подними `--stylize` в Midjourney или CFG 6→7 в SDXL.
- Все лица анимешные → добавь в negative `anime, big eyes, kawaii`.
- Размытость → AI на 24×32 не работает, **обязательно** генерь 1024×1024 и downscale в Aseprite (Resample: Nearest).
- Цвета не попадают в палитру → не парься, индексация в Aseprite сама подгонит. Главное чтобы общий тон был правильный (тёплый desat, без неона).
- Один спрайт упрямо плохой → пришли его мне, я напишу новый промпт под конкретный кейс или нарисую руками в Aseprite как референс.

## 8. Когда залил — ping me

Скажи в чате: **«NPCs готовы»** или просто запушь файлы в репо. Я сразу:
1. Запущу автоматический lint (палитра / размер / прозрачность / именование).
2. Воткну все 28 спрайтов в Godot-сцену в виде сетки 7×4 (культуры × роли).
3. Сделаю скриншот и пришлю — сразу увидишь, как смотрится твой арт в реальной игре.
4. Если всё ок — переходим к следующему узкому гайду (тайлы биомов, потом здания, потом UI).
