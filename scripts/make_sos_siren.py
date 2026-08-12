#!/usr/bin/env python3
"""Синтезирует сигнал SOS-вызова — двухтональную полицейскую сирену «пин-пон».

    python3 scripts/make_sos_siren.py

Перезаписывает три файла разом (все три обязаны быть одним и тем же звуком,
иначе вызов звучит по-разному в фоне и в открытом приложении):

    android/app/src/main/res/raw/sos_siren.mp3   петля, её крутит Android
    assets/sounds/sos_siren.mp3                  та же петля для игры в приложении
    ios/Runner/sos_siren.caf                     6 повторов подряд

Скрипт лежит в репозитории не для красоты: звук синтезированный, и без него это
просто бинарник, который никто не сможет ни повторить, ни подправить. Нужен
ffmpeg (`brew install ffmpeg`).

Почему именно такие числа
─────────────────────────
* **870 и 1160 Гц** — интервал ровно 3:4 (чистая кварта), тот самый, что у
  европейского двухтонального спецсигнала. Канонические 435/580 Гц подняты на
  октаву: динамик телефона ниже ~500 Гц почти ничего не отдаёт, а вторая и
  третья гармоники этой пары (1740–3480 Гц) попадают в самую чувствительную
  область слуха. Через карман и через стену слышно именно их.
* **0,6 с на тон**, 4 полных цикла = **4,8 с** петли — темп настоящего «пин-пон».
* Обе частоты укладываются в 4,8 с целым числом периодов (4176 и 5568), а число
  переключений тона за петлю чётное, поэтому конец сходится с началом бесшовно.
  Точка склейки приходится ровно на смену тона — даже если mp3-кодек добавит
  своё дополнение, разрыв ляжет туда, где звук и так меняется, и на слух не
  прочитается. У непрерывного воя (как было до этого) он щёлкал бы.
* **Гармоники** дают характер клаксона: чистая синусоида звучит как тест-сигнал,
  а не как спецсигнал.

Менять звук здесь безопасно: канал уведомления хранит ссылку по имени
(`android.resource://<пакет>/raw/sos_siren`), поэтому подмена содержимого файла
подхватывается сама. А вот громкость, важность канала или audio usage заморожены
при создании канала — их правка требует поднять суффикс `sos_siren_channel_v1`
в lib/core/notifications/sos_siren.dart.
"""

import math
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

SR = 44100
LOOP_SECONDS = 4.8
SEG_SECONDS = 0.6            # длительность одного тона
F_LO = 870.0                 # «пон»
F_HI = F_LO * 4 / 3          # «пин», 1160 Гц
XFADE_SECONDS = 0.012        # сглаживание стыка, чтобы не щёлкало
HARMONICS = (1.0, 0.50, 0.28, 0.14, 0.07)
PEAK = 0.92
IOS_REPEATS = 6              # 28,8 с: iOS играет звук уведомления один раз и режет всё длиннее 30 с

N = int(round(LOOP_SECONDS * SR))
SEG = int(round(SEG_SECONDS * SR))
XF = int(round(XFADE_SECONDS * SR))

assert N % SEG == 0, "петля должна делиться на сегменты нацело"
assert (N // SEG) % 2 == 0, "число переключений тона должно быть чётным, иначе стык слышен"
for _f in (F_LO, F_HI):
    _cycles = _f * LOOP_SECONDS
    assert abs(_cycles - round(_cycles)) < 1e-9, f"{_f} Гц не укладывается в петлю целым числом периодов"


def _tone(freq: float) -> list:
    """Непрерывный тон с гармониками на всю длину буфера."""
    out = [0.0] * N
    base = 2.0 * math.pi * freq / SR
    for h, amp in enumerate(HARMONICS, start=1):
        if freq * h >= SR / 2:
            break
        w = base * h
        for i in range(N):
            out[i] += amp * math.sin(w * i)
    return out


def _hi_weight(i: int) -> float:
    """Доля высокого тона в момент i. Считается по кругу, поэтому стык петли —
    такой же плавный переход, как и все остальные."""
    seg_index = i // SEG
    pos = i - seg_index * SEG
    target = 1.0 if seg_index % 2 == 0 else 0.0    # начинаем с «пин»
    if pos >= XF:
        return target
    previous = 1.0 - target                        # соседний сегмент всегда другой тон
    t = 0.5 - 0.5 * math.cos(math.pi * pos / XF)   # приподнятый косинус
    return previous + (target - previous) * t


def build_loop() -> list:
    hi, lo = _tone(F_HI), _tone(F_LO)
    mixed = []
    for i in range(N):
        w = _hi_weight(i)
        mixed.append(w * hi[i] + (1.0 - w) * lo[i])
    gain = PEAK / max(abs(s) for s in mixed)
    return [s * gain for s in mixed]


def write_wav(path: Path, samples: list, repeats: int = 1) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frame = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        for _ in range(repeats):
            w.writeframes(frame)


def encode(src: Path, dst: Path, *args: str) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(src), *args, str(dst)],
        check=True,
    )
    print(f"  ✓ {dst.relative_to(ROOT)}  ({dst.stat().st_size / 1024:.0f} КБ)")


ROOT = Path(__file__).resolve().parent.parent

if __name__ == "__main__":
    if subprocess.run(["which", "ffmpeg"], capture_output=True).returncode != 0:
        sys.exit("Нужен ffmpeg: brew install ffmpeg")

    print(f"Синтез: {F_LO:.0f} / {F_HI:.0f} Гц, по {SEG_SECONDS} с, петля {LOOP_SECONDS} с")
    loop = build_loop()

    with tempfile.TemporaryDirectory() as tmp:
        loop_wav = Path(tmp) / "loop.wav"
        ios_wav = Path(tmp) / "ios.wav"
        write_wav(loop_wav, loop)
        write_wav(ios_wav, loop, repeats=IOS_REPEATS)

        encode(loop_wav, ROOT / "android/app/src/main/res/raw/sos_siren.mp3",
               "-c:a", "libmp3lame", "-b:a", "64k", "-ac", "1")
        encode(loop_wav, ROOT / "assets/sounds/sos_siren.mp3",
               "-c:a", "libmp3lame", "-b:a", "64k", "-ac", "1")
        encode(ios_wav, ROOT / "ios/Runner/sos_siren.caf",
               "-c:a", "adpcm_ima_qt", "-f", "caf")

    print("Готово. Файлы перезаписаны — пересоберите приложение.")
