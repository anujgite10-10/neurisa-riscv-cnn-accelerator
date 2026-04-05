#!/usr/bin/env python3
"""
NEORV32 Image Generator - Python replacement for image_gen.c
Converts a RISC-V ELF file to NEORV32 bootloader-compatible executable format.

Usage: python image_gen.py -i main.elf -o neorv32_exe.bin -t exe

The bootloader EXE format:
  [4 bytes] signature  = 0x214F454E ("NEO!")
  [4 bytes] base_addr  = entry point from ELF
  [4 bytes] size       = total data size in bytes
  [4 bytes] checksum   = bitwise NOT of sum of all 32-bit data words
  [N bytes] raw data   = .text + .rodata + .data concatenated
"""

import struct
import sys
import argparse

# ELF constants
ELF_MAGIC = b'\x7fELF'
SHT_PROGBITS = 1
SHF_ALLOC = 0x2

def read_elf_sections(elf_data):
    """Parse ELF32 and extract loadable sections."""
    # ELF header
    if elf_data[:4] != ELF_MAGIC:
        raise ValueError("Not a valid ELF file!")

    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
     e_flags, e_ehsize, e_phentsize, e_phnum,
     e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from(
        '<HHIIIIIHHHHHH', elf_data, 16)

    print(f"  Entry point: 0x{e_entry:08X}")
    print(f"  Sections: {e_shnum}")

    # Read section headers
    sections = []
    for i in range(e_shnum):
        offset = e_shoff + i * e_shentsize
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset,
         sh_size, sh_link, sh_info, sh_addralign, sh_entsize) = struct.unpack_from(
            '<IIIIIIIIII', elf_data, offset)
        sections.append({
            'name_idx': sh_name, 'type': sh_type, 'flags': sh_flags,
            'addr': sh_addr, 'offset': sh_offset, 'size': sh_size
        })

    # Read section string table
    shstrtab = sections[e_shstrndx]
    strtab_data = elf_data[shstrtab['offset']:shstrtab['offset'] + shstrtab['size']]

    def get_name(idx):
        end = strtab_data.index(b'\x00', idx)
        return strtab_data[idx:end].decode('utf-8')

    # Extract .text, .rodata, .data
    text_data = b''
    rodata_data = b''
    data_data = b''

    for sec in sections:
        name = get_name(sec['name_idx'])
        if name == '.text':
            text_data = elf_data[sec['offset']:sec['offset'] + sec['size']]
            print(f"  .text:   {sec['size']:6d} bytes @ 0x{sec['addr']:08X}")
        elif name == '.rodata':
            rodata_data = elf_data[sec['offset']:sec['offset'] + sec['size']]
            print(f"  .rodata: {sec['size']:6d} bytes @ 0x{sec['addr']:08X}")
        elif name == '.data':
            data_data = elf_data[sec['offset']:sec['offset'] + sec['size']]
            print(f"  .data:   {sec['size']:6d} bytes @ 0x{sec['addr']:08X}")

    return e_entry, text_data + rodata_data + data_data


def generate_exe(entry, raw_data, output_path):
    """Generate NEORV32 bootloader-compatible executable."""
    signature = 0x214F454E  # "NEO!"
    size = len(raw_data)

    # Pad to 4-byte boundary
    while len(raw_data) % 4 != 0:
        raw_data += b'\x00'

    # Calculate checksum (sum of all 32-bit words)
    checksum = 0
    for i in range(0, len(raw_data), 4):
        word = struct.unpack_from('<I', raw_data, i)[0]
        checksum = (checksum + word) & 0xFFFFFFFF

    checksum = (~checksum) & 0xFFFFFFFF

    # Write output
    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', signature))
        f.write(struct.pack('<I', entry))
        f.write(struct.pack('<I', size))
        f.write(struct.pack('<I', checksum))
        f.write(raw_data)

    total = 16 + len(raw_data)
    print(f"\nExecutable (EXE): {size} bytes @ 0x{entry:08X}, checksum = 0x{checksum:08X}")
    print(f"Output file: {output_path} ({total} bytes total)")


def main():
    parser = argparse.ArgumentParser(description='NEORV32 Image Generator (Python)')
    parser.add_argument('-i', '--input', required=True, help='Input ELF file')
    parser.add_argument('-o', '--output', required=True, help='Output binary file')
    parser.add_argument('-t', '--type', default='exe', choices=['exe'], help='Output format')
    args = parser.parse_args()

    print(f"NEORV32 Image Generator (Python)")
    print(f"Reading: {args.input}")

    with open(args.input, 'rb') as f:
        elf_data = f.read()

    entry, raw_data = read_elf_sections(elf_data)

    if len(raw_data) == 0:
        print("[ERROR] No loadable sections found!")
        sys.exit(1)

    generate_exe(entry, raw_data, args.output)
    print("Done!")


if __name__ == '__main__':
    main()
