#!/usr/bin/env python3
"""Generate the small ASCII font and four boot-help pages used by video_output."""
from pathlib import Path

# Seven rows of five pixels, left to right. Each cell occupies 8x8 pixels.
FONT = {
    'A':'0E11111F111111', 'B':'1E11111E11111E', 'C':'0F10101010100F',
    'D':'1E11111111111E', 'E':'1F10101E10101F', 'F':'1F10101E101010',
    'G':'0F10101711110F', 'H':'1111111F111111', 'I':'0E04040404040E',
    'J':'0702020212120C', 'K':'11121418141211', 'L':'1010101010101F',
    'M':'111B1515111111', 'N':'11191513111111', 'O':'0E11111111110E',
    'P':'1E11111E101010', 'Q':'0E11111115120D', 'R':'1E11111E141211',
    'S':'0F10100E01011E', 'T':'1F040404040404', 'U':'1111111111110E',
    'V':'11111111110A04', 'W':'11111115151B11', 'X':'11110A040A1111',
    'Y':'11110A04040404', 'Z':'1F01020408101F',
    '0':'0E11131519110E', '1':'040C040404040E', '2':'0E11010204081F',
    '3':'1E01010E01011E', '4':'02060A121F0202', '5':'1F10101E01011E',
    '6':'0E10101E11110E', '7':'1F010204080808', '8':'0E11110E11110E',
    '9':'0E11110F01010E', '.':'00000000000C0C', '/':'01010204081010',
    '-':'0000001F000000', ' ':'00000000000000',
}
PAGES = [
    ['ZET98', '', 'BOOT.ROM REQUIRED', '', 'COPY BOOT.ROM TO THE',
     'GAME FOLDER FOR THIS CORE', '', 'THEN RELOAD THE CORE'],
    ['ZET98', '', 'PLEASE INSERT DISK', '', 'PRESS F12 AND SELECT FDD0',
     'OR SELECT IDE HARD DISK', '', 'RAW PC-98 VHD OR IMG'],
    ['ZET98', '', 'STARTING HARD DISK', '', 'PLEASE WAIT', '', '', ''],
    ['ZET98', '', 'LOADING DISK', '', 'PLEASE WAIT', '', '', ''],
]


def generate(folder):
    pixels = [0] * 1024
    for ch, rows in FONT.items():
        pixels[ord(ch)*8:ord(ch)*8+7] = [r << 2 for r in bytes.fromhex(rows)]
    text = []
    for page in PAGES:
        assert len(page) == 8
        for line in page:
            assert len(line) <= 32
            assert all(ch in FONT for ch in line)
            text.extend(map(ord, line.center(32)))
    folder.mkdir(parents=True, exist_ok=True)
    for name, data in [('boot-font.mem', pixels), ('boot-text.mem', text)]:
        (folder / name).write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')


if __name__ == '__main__':
    generate(Path(__file__).resolve().parents[1] / 'rtl/assets')
