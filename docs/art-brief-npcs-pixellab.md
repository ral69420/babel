# NPC quickstart — PixelLab edition

`art-brief-npcs.md` написан под универсальный AI (SDXL / MJ / ChatGPT). PixelLab — специализированный инструмент с собственными настройками, в его Character/Animation генераторе мой длинный промпт интерпретируется как «много вариаций, много направлений, анимация» и на выходе получается сразу 64 файла.

Этот файл — короткий правильный workflow именно для PixelLab.

## 1. Какой генератор открыть

PixelLab имеет несколько режимов. Нам нужен **Character** (одиночный спрайт), **не Animation**, **не Spritesheet**.

## 2. Настройки

| опция | значение |
|---|---|
| **Rotations / Directions / Views** | **1** (только front) |
| **Animation / Animated** | **off** |
| **Variants per generation** | **1** (если есть выбор) |
| **Size / Canvas** | 64×64 или 96×96 (потом downscale в Aseprite до 24×32) |
| **Style** | Pixel Art / Cozy / RPG (если есть дропдаун) |
| **Outline** | Off / None (если есть переключатель) |

Если PixelLab всё равно выдаёт несколько кадров — значит включена анимация / поворот. Выключи их в настройках, не в промпте.

## 3. Что писать в поле Description

Только **короткую** строку, описывающую персонажа. **Без** мастер-префикса из общего гайда. PixelLab внутренне знает про «pixel art / 3/4 / no outline» и при добавлении этого в промпт может ломаться.

Шаблон:
```
{culture descriptor}, {clothing}, {accessory/item in hands}, {hair/skin}, facing camera 3/4 view
```

Готовые 28 коротких строк — ниже. Скопировал из основного гайда и обрезал хвосты, чтобы PixelLab не путался.

### kheltari
- **commoner** — `kheltari mountain herder, slate grey-blue wool tunic over bone-cream undershirt, leather belt and boots, holding small woven basket, cropped dark hair, copper buckle, facing camera 3/4 view`
- **elder** — `kheltari mountain elder, long slate-blue wool robe with bone-cream embroidered hem, gnarled walking staff, full grey beard, copper amulet of carved stone, facing camera 3/4 view`
- **warrior** — `kheltari mountain warrior, slate-blue ringmail over wool gambeson, round wooden shield on back, sheathed sword at hip, scarred jaw, riveted iron helmet, facing camera 3/4 view`
- **priest** — `kheltari mountain priest, pale grey hooded robe with bone-cream stone-circle motif on chest, copper sun-disk amulet, no beard, palms open, facing camera 3/4 view`

### orunmare
- **commoner** — `orunmare savannah villager, ochre linen wrap with sunset-orange sash, brass anklets, dark warm skin, long braided hair, holding clay water gourd, bare feet, facing camera 3/4 view`
- **elder** — `orunmare savannah elder, deep-ochre layered linen robe, brass armbands and sun-disk pendant, long staff with carved acacia bird, white hair in braids, dark warm skin, facing camera 3/4 view`
- **warrior** — `orunmare savannah warrior, ochre leather cuirass with brass studs, sunset-orange shoulder cape, sheathed curved sword, oval hide shield slung, dark warm skin, ochre marks under eyes, facing camera 3/4 view`
- **priest** — `orunmare savannah priest, white-and-ochre linen robe with brass-disk collar, head wrapped in cream cloth, dark warm skin, holding small brass bowl, facing camera 3/4 view`

### dvarni
- **commoner** — `dvarni forest peasant, dark mossy-green wool tunic, brown fur-trimmed vest, iron belt buckle, carrying axe handle, pale weathered skin, dark hair, leather boots, facing camera 3/4 view`
- **elder** — `dvarni forest elder, long dark-green wool robe, heavy wolfskin cloak, iron-tipped staff, iron-grey beard, pale weathered face, bone amulet, facing camera 3/4 view`
- **warrior** — `dvarni forest warrior, dark-green leather and iron lamellar, wolfskin shoulder mantle, sheathed bearded axe at hip, round iron-rimmed wooden shield slung, dark braided beard, facing camera 3/4 view`
- **priest** — `dvarni forest priest, ash-grey hooded robe with dark-green tree-rune embroidery, antler-tip pendant, pale skin, holding bundle of birch twigs, facing camera 3/4 view`

### eluran
- **commoner** — `eluran coastal villager, pale-teal linen tunic, bleached cream sash, sun-kissed skin, salt-bleached hair, holding rolled fishing net, bare feet, facing camera 3/4 view`
- **elder** — `eluran coastal elder, layered teal-and-cream linen robe, mother-of-pearl pendant, thin coral staff, white hair tied back, sun-kissed weathered skin, facing camera 3/4 view`
- **warrior** — `eluran coastal warrior, pale-teal leather scale armor with cream cloth wrap, sheathed thin curved blade, light wicker shield slung, sun-kissed skin, hair pulled back, facing camera 3/4 view`
- **priest** — `eluran coastal priest, bleached cream robe with teal embroidered wave pattern, pearl-string circlet, sun-kissed skin, holding small shell bowl, facing camera 3/4 view`

### qarasil
- **commoner** — `qarasil desert nomad, sand-bone layered linen wraps, deep indigo veil covering lower face and head, tan skin, only dark eyes visible, holding rolled travel mat, sandals, facing camera 3/4 view`
- **elder** — `qarasil desert elder, full sand-bone robe and indigo head-wrap, indigo half-veil lowered to chin, white beard, deep tan weathered skin, carved staff with brass cap, facing camera 3/4 view`
- **warrior** — `qarasil desert warrior, sand-bone wraps over indigo undertunic, indigo veil up covering lower face, sheathed scimitar, small round metal shield slung, leather bracers, fierce dark eyes, facing camera 3/4 view`
- **priest** — `qarasil desert priest, deep indigo hooded robe with sand-bone constellation pattern stitched, brass star-pendant, indigo lower-face veil, holding tiny brass mirror, facing camera 3/4 view`

### ningaer
- **commoner** — `ningaer river farmer, jade-green linen tunic with reed-tan trousers rolled to knees, conical straw hat, warm tan skin, holding wooden rice paddle, bare feet, facing camera 3/4 view`
- **elder** — `ningaer river elder, long jade-green silk robe with reed-tan sash, wide conical straw hat, carved bamboo staff, white wispy beard, warm tan skin, facing camera 3/4 view`
- **warrior** — `ningaer river warrior, jade-green lacquered scale over reed-tan padded tunic, iron-rimmed conical straw hat, sheathed thin straight sword, slim build, warm tan skin, facing camera 3/4 view`
- **priest** — `ningaer river priest, soft jade-green silk robe with reed-tan stole, head shaved, warm tan skin, holding bundle of fragrant reeds, facing camera 3/4 view`

### sankhara
- **commoner** — `sankhara plateau ascetic worker, ash-grey rough-spun robe with dusty-violet sash, shaved head, fair skin, simple wooden bowl in hands, bare feet, facing camera 3/4 view`
- **elder** — `sankhara plateau elder, layered dusty-violet and ash-grey robes, heavy wooden prayer beads, shaved head with thin white topknot, fair lined skin, plain staff with violet ribbon, facing camera 3/4 view`
- **warrior** — `sankhara plateau warden, ash-grey padded robe under dusty-violet cuirass, sheathed straight monk sword, shaved head with thin warrior topknot, prayer beads on left wrist, facing camera 3/4 view`
- **priest** — `sankhara plateau priest, deep dusty-violet ceremonial robe with magic-violet sigils embroidered, ash-grey under-robe, shaved head, fair skin, holding small bronze bell, facing camera 3/4 view`

## 4. После генерации

PixelLab выдаёт PNG на 64×64 / 96×96 / etc. Прогоняем через Aseprite:

1. Открыть PNG в Aseprite.
2. `Sprite → Sprite Size → New size 24×32 → Resample: Nearest → OK`.
3. `Sprite → Color Mode → Indexed → Use a custom palette → Open palette → godot_project/assets/palette/babel_v1.gpl`.
4. `Layer → Background from layer` если фон не прозрачный (потом стереть фон ластиком).
5. `File → Export → ровно тот путь:` `godot_project/assets/npcs/{culture}/{archetype}_idle.png`.

## 5. Если 64 файла продолжают появляться

Скорее всего активирован **Animation** или **Rotation** режим. Скинь мне скриншот настроек PixelLab (тот сайдбар где выбираются опции генерации) — я скажу точно, какие тоглы выключить.
