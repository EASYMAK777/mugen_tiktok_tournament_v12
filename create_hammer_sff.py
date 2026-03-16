"""
Converts hammer PNG to SFF v2 format for IkemenGO.
Usage: python create_hammer_sff.py
"""

import struct
import io
import os
from PIL import Image


def image_to_png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def create_sff(sprites, output_path):
    """
    sprites: list of (group, index, png_bytes, width, height)
    Writes SFF v2 file matching IkemenGO's expected format.
    """
    HEADER_SIZE = 512
    SPRITE_NODE_SIZE = 28

    num_sprites = len(sprites)
    num_palettes = 0

    pal_list_offset = HEADER_SIZE
    sprite_list_offset = pal_list_offset
    ldata_offset = sprite_list_offset + num_sprites * SPRITE_NODE_SIZE

    ldata = bytearray()
    sprite_entries = []
    for group, index, png_data, w, h in sprites:
        data_off = len(ldata)
        uncomp_size = w * h * 4
        ldata.extend(struct.pack('<I', uncomp_size))
        ldata.extend(png_data)
        total_len = 4 + len(png_data)
        sprite_entries.append((group, index, w, h, data_off, total_len))

    ldata_length = len(ldata)
    tdata_offset = ldata_offset + ldata_length
    tdata_length = 0

    out = bytearray()

    header = bytearray(HEADER_SIZE)
    header[0:12] = b'ElecbyteSpr\x00'
    header[12] = 0; header[13] = 1; header[14] = 0; header[15] = 2
    header[24] = 0; header[25] = 1; header[26] = 0; header[27] = 2
    struct.pack_into('<I', header, 36, sprite_list_offset)
    struct.pack_into('<I', header, 40, num_sprites)
    struct.pack_into('<I', header, 44, pal_list_offset)
    struct.pack_into('<I', header, 48, num_palettes)
    struct.pack_into('<I', header, 52, ldata_offset)
    struct.pack_into('<I', header, 56, ldata_length)
    struct.pack_into('<I', header, 60, tdata_offset)
    struct.pack_into('<I', header, 64, tdata_length)
    out.extend(header)

    for group, index, w, h, data_off, data_len in sprite_entries:
        node = bytearray(SPRITE_NODE_SIZE)
        struct.pack_into('<H', node, 0, group)
        struct.pack_into('<H', node, 2, index)
        struct.pack_into('<H', node, 4, w)
        struct.pack_into('<H', node, 6, h)
        struct.pack_into('<h', node, 8, w // 2)   # axis x (center)
        struct.pack_into('<h', node, 10, h // 2)   # axis y (center)
        struct.pack_into('<H', node, 12, 0)
        node[14] = 12                               # PNG32
        node[15] = 32
        struct.pack_into('<I', node, 16, data_off)
        struct.pack_into('<I', node, 20, data_len)
        struct.pack_into('<H', node, 24, 0)
        struct.pack_into('<H', node, 26, 0)
        out.extend(node)

    out.extend(ldata)

    with open(output_path, 'wb') as f:
        f.write(out)

    return len(out)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_png = os.path.join(os.path.dirname(script_dir), "hammer_pixel_art_5x_flipped.png")

    # Also check Desktop directly
    if not os.path.exists(input_png):
        input_png = r"C:\Users\juanf\OneDrive\Desktop\hammer_pixel_art_5x_flipped.png"

    output_sff = os.path.join(script_dir, "external", "mods", "hammer.sff")

    print("=" * 50)
    print("  HAMMER SFF GENERATOR")
    print("=" * 50)

    img = Image.open(input_png).convert("RGBA")
    print(f"  Input: {input_png}")
    print(f"  Size: {img.size[0]}x{img.size[1]}")

    png_data = image_to_png_bytes(img)
    sprites = [(0, 0, png_data, img.size[0], img.size[1])]

    file_size = create_sff(sprites, output_sff)
    print(f"  Output: {output_sff}")
    print(f"  SFF size: {file_size:,} bytes")
    print()
    print("  Done! hammer.sff is ready.")


if __name__ == "__main__":
    main()
