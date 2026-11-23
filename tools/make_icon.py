#!/usr/bin/env python3
"""Generates LiveSnap's 1024pt app icon using only the standard library."""

import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "LiveSnap", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
)


def smoothstep(edge0, edge1, value):
    if edge1 <= edge0:
        return 0.0 if value < edge0 else 1.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def ring(radius_distance, target, width):
    inner = target - width / 2.0
    outer = target + width / 2.0
    return smoothstep(inner - 1.2, inner + 1.2, radius_distance) * (
        1.0 - smoothstep(outer - 1.2, outer + 1.2, radius_distance)
    )


def render():
    pixels = bytearray(SIZE * SIZE * 3)
    center = SIZE / 2.0

    for y in range(SIZE):
        fy = y / SIZE
        for x in range(SIZE):
            fx = x / SIZE

            violet_glow = math.exp(-(((fx - 0.22) ** 2 + (fy - 0.14) ** 2) / 0.14))
            amber_glow = math.exp(-(((fx - 0.86) ** 2 + (fy - 0.92) ** 2) / 0.20))
            vignette = 1.0 - 0.5 * smoothstep(0.30, 1.30, math.hypot(fx - 0.5, fy - 0.45))

            r = 9.0 * vignette + 96.0 * violet_glow + 30.0 * amber_glow
            g = 13.0 * vignette + 48.0 * violet_glow + 20.0 * amber_glow
            b = 28.0 * vignette + 158.0 * violet_glow + 10.0 * amber_glow

            dx = x - center
            dy = y - center
            distance = math.hypot(dx, dy)

            alpha = max(
                0.92 * ring(distance, 300.0, 26.0),
                0.68 * ring(distance, 206.0, 15.0),
                1.0 - smoothstep(86.0, 92.0, distance),
            )

            if alpha > 0.0:
                tint = smoothstep(0.20, 0.95, fy)
                lr = 255.0 - 24.0 * tint
                lg = 246.0 - 44.0 * tint
                lb = 234.0 - 98.0 * tint
                w = min(1.0, alpha)
                r = r * (1.0 - w) + lr * w
                g = g * (1.0 - w) + lg * w
                b = b * (1.0 - w) + lb * w

            index = (y * SIZE + x) * 3
            pixels[index] = max(0, min(255, int(r)))
            pixels[index + 1] = max(0, min(255, int(g)))
            pixels[index + 2] = max(0, min(255, int(b)))

    return pixels


def write_png(path, width, height, pixels):
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])

    def chunk(tag, payload):
        checksum = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", checksum))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(bytes([137, 80, 78, 71, 13, 10, 26, 10]))
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


def main():
    pixels = render()
    write_png(OUT, SIZE, SIZE, pixels)
    print("icon written:", OUT)


if __name__ == "__main__":
    main()
