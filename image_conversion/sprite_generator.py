"""
@file sprite_generator.py
@brief Converts an input image into MIPS assembly code that draws the image pixel by pixel.
       The script resizes the image to 256x256, extracts pixel RGB values, and outputs
       assembly instructions to write them into memory at 0x10008000.

@author Daniil Trukhin (daniilvtrukhin@gmail.com)

@date
2025-04-05
"""

from PIL import Image


def gen_asm_image(image_path, threshhold=10):
    img = Image.open(image_path).convert("RGB")
    img = img.resize((256, 256), Image.Resampling.LANCZOS)  # LANCZOS = better quality
    pixels = img.load()

    lines = ["    la $t0, 0x10008000", ""]
    for x in range(256):
        for y in range(256):
            r, g, b = pixels[x, y]
            offset = y * 256 + x
            byte_offset = offset * 4

            color = (r << 16) | (g << 8) | b

            # if r > threshold and g < threshold and b < threshhold:
            #     color = 0x00FFFFFF
            #     lines.append(f"    li $t1, 0x{color:08x}  # pixel at ({x}, {y})")
            #     lines.append(f"    sw $t1, {byte_offset}($t0)")
            #
            # if r > threshhold and g > threshhold and b > threshhold:
            #     color = 0x00FFFFFF  # white
            #     lines.append(f"    li $t1, 0x{color:08x}  # pixel at ({x}, {y})")
            #     lines.append(f"    sw $t1, {byte_offset}($t0)")

            lines.append(f"    li $t1, 0x{color:08x}  # pixel at ({x}, {y})")
            lines.append(f"    sw $t1, {byte_offset}($t0)")
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    with open("pause_screen.asm", "w") as f:
        f.write(gen_asm_image("pause_screen.png"))
    print("DONE!")
