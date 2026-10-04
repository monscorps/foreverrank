#!/usr/bin/env python3
"""Build QuestBank-Uploader.zip: the Windows uploader plus the QuestBank addon it installs.

Run from anywhere:  python3 tools/build_uploader.py [--out PATH] [--icon] [--test]

The zip holds two folders:
  QuestBank Uploader/   Install.bat, Uninstall.bat, QuestBank-Uploader.ps1, README.txt, QuestBank.ico
  QuestBank/            the addon, as tools/questbank/QuestBank is now (Install.bat puts it in AddOns)

Default output is questbank/QuestBank-Uploader.zip. The icon (uploader/QuestBank.ico) is drawn
here when it is missing, or again with --icon. Text files go in with CRLF line ends (cmd.exe reads
a .bat line by line and LF-only files have tripped it), and the .ps1 must be plain ASCII: Windows
PowerShell 5.1 reads a script without a byte-order mark in the system code page, which on a
Norwegian or any other non-English Windows turns other characters into something else.
The zip carries no key: the uploader posts to the site's open upload endpoint.

--test builds into a temporary folder instead and runs uploader/tests/test.ps1 against that zip in
Docker (mcr.microsoft.com/dotnet/sdk:8.0, no network). Both go in on stdin, since Docker on a Mac
doesn't see /private/tmp.
"""
import argparse, io, os, re, subprocess, sys, tarfile, tempfile, time, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "uploader")
ADDON = os.path.join(ROOT, "tools", "questbank", "QuestBank")
ICON = os.path.join(SRC, "QuestBank.ico")
TEXT = ("Install.bat", "Uninstall.bat", "QuestBank-Uploader.ps1", "README.txt")


def draw_book(size, small=False):
    """QuestBank's mark for the tray: a closed leather quest book with a gold "!" (drawn here, no game art).
    The small version (16-24 pixels, the tray's own sizes) drops the corner caps and spine bands and
    widens the "!", which otherwise blur into the cover."""
    from PIL import Image, ImageDraw
    S = 8  # oversample, then scale down
    N = size * S
    k = N / 64.0
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    def box(x0, y0, x1, y1):
        return [x0 * k, y0 * k, x1 * k, y1 * k]
    ink = (38, 22, 10, 255)
    # the page block, showing at the right and bottom edges
    d.rounded_rectangle(box(14, 8, 58, 61), radius=3 * k, fill=(236, 222, 184, 255), outline=ink, width=int(2 * k))
    for y in (52, 55):
        d.line(box(18, y, 55, y), fill=(176, 150, 104, 255), width=int(1 * k))
    # the cover and its darker spine
    d.rounded_rectangle(box(6, 3, 53, 56), radius=4 * k, fill=(122, 74, 34, 255), outline=ink, width=int(2 * k))
    d.rounded_rectangle(box(6, 3, 17, 56), radius=4 * k, fill=(84, 48, 20, 255), outline=ink, width=int(2 * k))
    gold = (229, 204, 128, 255)
    cx = 35.5
    if small:
        # the "!" alone, wide and bright
        bright = (255, 222, 120, 255)
        d.rectangle(box(cx - 5, 11, cx + 5, 36), fill=bright)
        d.rectangle(box(cx - 5, 41, cx + 5, 50), fill=bright)
        return img.resize((size, size), Image.LANCZOS)
    for y in (11, 47):
        d.rectangle(box(7, y, 16, y + 3), fill=gold)
    # gold corner caps on the cover's open edge
    d.polygon([(53 * k, 3 * k), (41 * k, 3 * k), (53 * k, 15 * k)], fill=gold, outline=ink)
    d.polygon([(53 * k, 56 * k), (41 * k, 56 * k), (53 * k, 44 * k)], fill=gold, outline=ink)
    # the "!" in the middle of the cover, outlined
    d.rounded_rectangle(box(cx - 5, 12, cx + 5, 37), radius=4 * k, fill=ink)
    d.rounded_rectangle(box(cx - 3, 14, cx + 3, 35), radius=3 * k, fill=gold)
    d.ellipse(box(cx - 5.5, 40, cx + 5.5, 51), fill=ink)
    d.ellipse(box(cx - 3.5, 42, cx + 3.5, 49), fill=gold)
    return img.resize((size, size), Image.LANCZOS)


def write_icon():
    # each size drawn on its own; the .ico keeps them all and Windows picks the one it needs
    sizes = [16, 20, 24, 32, 48, 64, 128, 256]
    imgs = [draw_book(n, small=n <= 24) for n in sizes]
    imgs[-1].save(ICON, sizes=[(n, n) for n in sizes], append_images=imgs[:-1])
    print("drew", os.path.relpath(ICON, ROOT))


def toc_version(toc):
    with open(toc, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"^##\s*Version:\s*(\S+)", line)
            if m:
                return m.group(1)
    return None


def core_version(core):
    with open(core, encoding="utf-8", errors="replace") as f:
        m = re.search(r'^QB\.version\s*=\s*"([^"]+)"', f.read(), re.M)
    return m.group(1) if m else None


def check_addon():
    """The addon folder must load: a .toc with a version, and every file it lists present. Core.lua's
    QB.version must be the same: QuestBank writes it into QuestBank.lua, and the uploader's Status
    compares that with the installed .toc's to tell whether WoW still runs an older QuestBank."""
    toc = os.path.join(ADDON, "QuestBank.toc")
    if not os.path.isfile(toc):
        sys.exit("no " + os.path.relpath(toc, ROOT))
    ver = toc_version(toc)
    if not ver:
        sys.exit("QuestBank.toc has no ## Version line")
    core = core_version(os.path.join(ADDON, "Core.lua"))
    if core != ver:
        sys.exit("QuestBank.toc says Version %s but Core.lua says QB.version = %s" % (ver, core))
    with open(toc, encoding="utf-8", errors="replace") as f:
        for line in f:
            name = line.strip()
            if not name or name.startswith("#"):
                continue
            if not os.path.isfile(os.path.join(ADDON, name.replace("\\", "/"))):
                sys.exit("QuestBank.toc lists " + name + ", which is not in the folder")
    return ver


def crlf(data):
    return data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def add_bytes(zf, arc, data, src):
    info = zipfile.ZipInfo(arc, date_time=time.localtime(os.path.getmtime(src))[:6])
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def add_dir(zf, arc):
    info = zipfile.ZipInfo(arc.rstrip("/") + "/", date_time=time.localtime()[:6])
    info.external_attr = (0o40755 << 16) | 0x10
    zf.writestr(info, b"")


def run_tests(zip_path):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tf:
        tf.add(os.path.join(SRC, "tests", "test.ps1"), "test.ps1")
        tf.add(zip_path, "QuestBank-Uploader.zip")
    cmd = ["docker", "run", "-i", "--rm", "--network", "none", "mcr.microsoft.com/dotnet/sdk:8.0", "sh", "-c",
           "mkdir /w && tar -C /w -xf - 2>/dev/null && pwsh -NoProfile -File /w/test.ps1"]
    return subprocess.run(cmd, input=buf.getvalue()).returncode


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "questbank", "QuestBank-Uploader.zip"))
    ap.add_argument("--icon", action="store_true", help="draw uploader/QuestBank.ico again")
    ap.add_argument("--test", action="store_true", help="build into a temporary folder and run the tests in Docker")
    a = ap.parse_args()

    if a.icon or not os.path.exists(ICON):
        write_icon()
    ver = check_addon()
    if a.test:
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "QuestBank-Uploader.zip")
            build(out, ver)
            sys.stdout.flush()
            sys.exit(run_tests(out))
    build(os.path.abspath(a.out), ver)


def build(out, ver):
    ps1 = open(os.path.join(SRC, "QuestBank-Uploader.ps1"), "rb").read()
    bad = [i for i, b in enumerate(ps1) if b > 127]
    if bad:
        line = ps1[:bad[0]].count(b"\n") + 1
        sys.exit("QuestBank-Uploader.ps1 has a non-ASCII character on line %d" % line)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
        add_dir(zf, "QuestBank Uploader/")
        for name in TEXT:
            src = os.path.join(SRC, name)
            add_bytes(zf, "QuestBank Uploader/" + name, crlf(open(src, "rb").read()), src)
        add_bytes(zf, "QuestBank Uploader/QuestBank.ico", open(ICON, "rb").read(), ICON)
        add_dir(zf, "QuestBank/")
        for base, dirs, files in os.walk(ADDON):
            dirs[:] = sorted(x for x in dirs if not x.startswith("."))
            rel = os.path.relpath(base, ADDON)
            if rel != ".":
                add_dir(zf, "QuestBank/" + rel.replace(os.sep, "/"))
            for f in sorted(files):
                if f.startswith("."):
                    continue
                src = os.path.join(base, f)
                arc = "QuestBank/" + os.path.relpath(src, ADDON).replace(os.sep, "/")
                add_bytes(zf, arc, open(src, "rb").read(), src)
    os.replace(tmp, out)

    print("wrote", out, os.path.getsize(out) // 1024, "KB, with QuestBank", ver)
    for i in zipfile.ZipFile(out).infolist():
        print("  %9d  %s" % (i.file_size, i.filename))


if __name__ == "__main__":
    main()
