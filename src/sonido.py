# Genera el sonido de inicio de RogerOS (acorde sintetizado ascendente con eco)
import math, struct, wave, sys
SR = 44100
notas = [(0.00, 220.00), (0.12, 329.63), (0.24, 440.00), (0.36, 554.37), (0.48, 659.25)]
dur = 2.6
n = int(SR * dur)
buf = [0.0] * n
for t0, f in notas:
    for i in range(int(SR * 1.8)):
        t = i / SR
        env = min(1, t / 0.02) * math.exp(-t * 2.2)
        s = (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2.003 * t)
             + 0.15 * math.sin(2 * math.pi * f * 3.01 * t)) * env
        j = int((t0 + t) * SR)
        if j < n: buf[j] += s
for d, g in ((int(SR * 0.23), 0.35), (int(SR * 0.46), 0.18)):
    for j in range(n - 1, d - 1, -1):
        buf[j] += buf[j - d] * g
pico = max(abs(x) for x in buf)
with wave.open(sys.argv[1], "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(x / pico * 0.6 * 32767)) for x in buf))
