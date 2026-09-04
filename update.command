#!/bin/bash
set -u
cd "$(dirname "$0")" || exit 1

INCOMING_DIR="incoming"
ARCHIVE_DIR="archive"
CURRENT_FILE="current.jpg"
ARCHIVE_JSON="archive.json"

if [ ! -d ".git" ]; then
  osascript -e 'display alert "저장소를 찾을 수 없습니다" message "update.command를 reflection-of-time 저장소의 최상위 폴더에 넣어주세요." as warning'
  exit 1
fi

mkdir -p "$INCOMING_DIR" "$ARCHIVE_DIR"
find . -name '.DS_Store' -type f -delete 2>/dev/null || true

WORK_FILE="$(mktemp -t reflection_work)"
SUCCESS_FILE="$(mktemp -t reflection_success)"
FAILED_FILE="$(mktemp -t reflection_failed)"
trap 'rm -f "$WORK_FILE" "$SUCCESS_FILE" "$FAILED_FILE"' EXIT

FOUND_COUNT=0

while IFS= read -r SOURCE_FILE; do
  [ -f "$SOURCE_FILE" ] || continue
  FOUND_COUNT=$((FOUND_COUNT + 1))

  # JPEG는 EXIF DateTimeOriginal(실제 촬영시각)을 파일에서 직접 읽습니다.
  # 그 값이 없거나 직접 읽을 수 없는 형식(예: HEIC)이면 macOS 메타데이터로 보완합니다.
  LOCAL_TIME="$(python3 - "$SOURCE_FILE" <<'PY'
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])

def exif_datetime_original_jpeg(p: Path):
    """JPEG APP1/Exif의 DateTimeOriginal(0x9003)을 외부 패키지 없이 직접 읽습니다."""
    data = p.read_bytes()
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None

    pos = 2
    while pos + 4 <= len(data):
        if data[pos] != 0xFF:
            pos += 1
            continue

        while pos < len(data) and data[pos] == 0xFF:
            pos += 1
        if pos >= len(data):
            break

        marker = data[pos]
        pos += 1

        if marker in (0xDA, 0xD9):  # SOS / EOI
            break
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        if pos + 2 > len(data):
            break

        seglen = struct.unpack(">H", data[pos:pos+2])[0]
        if seglen < 2 or pos + seglen > len(data):
            break
        seg = data[pos+2:pos+seglen]

        if marker == 0xE1 and seg.startswith(b"Exif\x00\x00"):
            tiff = seg[6:]
            if len(tiff) < 8:
                return None

            byte_order = tiff[:2]
            if byte_order == b"II":
                endian = "<"
            elif byte_order == b"MM":
                endian = ">"
            else:
                return None

            def u16(off):
                return struct.unpack(endian + "H", tiff[off:off+2])[0]

            def u32(off):
                return struct.unpack(endian + "I", tiff[off:off+4])[0]

            if u16(2) != 42:
                return None

            def read_ifd(offset):
                if offset < 0 or offset + 2 > len(tiff):
                    return []
                count = u16(offset)
                entries = []
                base = offset + 2
                for i in range(count):
                    off = base + i * 12
                    if off + 12 > len(tiff):
                        break
                    tag = u16(off)
                    typ = u16(off + 2)
                    cnt = u32(off + 4)
                    val = tiff[off + 8:off + 12]
                    entries.append((tag, typ, cnt, val))
                return entries

            ifd0 = u32(4)
            exif_ifd = None
            for tag, typ, cnt, val in read_ifd(ifd0):
                if tag == 0x8769:  # ExifIFDPointer
                    exif_ifd = struct.unpack(endian + "I", val)[0]
                    break
            if exif_ifd is None:
                return None

            for tag, typ, cnt, val in read_ifd(exif_ifd):
                if tag == 0x9003 and typ == 2 and cnt > 0:  # DateTimeOriginal
                    if cnt <= 4:
                        raw = val[:cnt]
                    else:
                        off = struct.unpack(endian + "I", val)[0]
                        raw = tiff[off:off+cnt]
                    s = raw.split(b"\x00", 1)[0].decode("ascii", "ignore").strip()
                    try:
                        return datetime.strptime(s, "%Y:%m:%d %H:%M:%S")
                    except ValueError:
                        return None
            return None

        pos += seglen

    return None

def read_mdls(key: str) -> str:
    result = subprocess.run(
        ["mdls", "-raw", "-name", key, str(path)],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()

dt = None

# 1순위: JPEG EXIF DateTimeOriginal 직접 판독
try:
    dt = exif_datetime_original_jpeg(path)
except Exception:
    dt = None

# 2순위: HEIC 등은 macOS가 인식한 콘텐츠 생성시각 사용
if dt is None:
    subprocess.run(["mdimport", str(path)], capture_output=True, text=True)
    raw = read_mdls("kMDItemContentCreationDate")
    if raw and raw != "(null)":
        for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S"):
            try:
                parsed = datetime.strptime(raw, fmt)
                dt = parsed.astimezone().replace(tzinfo=None) if parsed.tzinfo else parsed
                break
            except ValueError:
                pass

# 3순위: 파일 생성시각
if dt is None:
    raw = read_mdls("kMDItemFSCreationDate")
    if raw and raw != "(null)":
        for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S"):
            try:
                parsed = datetime.strptime(raw, fmt)
                dt = parsed.astimezone().replace(tzinfo=None) if parsed.tzinfo else parsed
                break
            except ValueError:
                pass

# 최후 fallback
if dt is None:
    dt = datetime.now()

print(dt.strftime("%Y-%m-%d %H:%M:%S"))
PY
)"

  printf '%s\t%s\n' "$LOCAL_TIME" "$SOURCE_FILE" >> "$WORK_FILE"
done <<EOF
$(find "$INCOMING_DIR" -maxdepth 1 -type f ! -name '.DS_Store' ! -name 'README.txt' | sort)
EOF

if [ "$FOUND_COUNT" -eq 0 ]; then
  osascript -e 'display alert "사진이 없습니다" message "incoming 폴더에 사진을 한 장 이상 넣은 뒤 다시 실행하세요." as warning'
  exit 1
fi

sort "$WORK_FILE" -o "$WORK_FILE"

while IFS="$(printf '\t')" read -r LOCAL_TIME SOURCE_FILE; do
  [ -n "${SOURCE_FILE:-}" ] || continue

  STAMP="$(python3 - "$LOCAL_TIME" <<'PY'
from datetime import datetime
import sys
print(datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M:%S").strftime("%Y%m%d_%H%M%S"))
PY
)"
  LABEL="$(python3 - "$LOCAL_TIME" <<'PY'
from datetime import datetime
import sys
print(datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M:%S").strftime("%Y.%m.%d %H:%M:%S"))
PY
)"

  TARGET="$ARCHIVE_DIR/${STAMP}.jpg"
  N=2
  while [ -e "$TARGET" ]; do
    TARGET="$ARCHIVE_DIR/${STAMP}_${N}.jpg"
    N=$((N + 1))
  done

  if sips -s format jpeg "$SOURCE_FILE" --out "$TARGET" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\t%s\n' "$LOCAL_TIME" "$SOURCE_FILE" "$TARGET" "$LABEL" >> "$SUCCESS_FILE"
  else
    printf '%s\n' "$SOURCE_FILE" >> "$FAILED_FILE"
  fi
done < "$WORK_FILE"

SUCCESS_COUNT="$(wc -l < "$SUCCESS_FILE" | tr -d ' ')"
FAILED_COUNT="$(wc -l < "$FAILED_FILE" | tr -d ' ')"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
  osascript -e 'display alert "처리 실패" message "사진을 JPEG로 변환하지 못했습니다. incoming 폴더의 원본은 그대로 남아 있습니다." as warning'
  exit 1
fi

python3 - "$ARCHIVE_JSON" "$SUCCESS_FILE" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
success_path = Path(sys.argv[2])

try:
    items = json.loads(json_path.read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    items = []

new_items = []
for line in success_path.read_text(encoding="utf-8").splitlines():
    parts = line.split("\t", 3)
    if len(parts) == 4:
        new_items.append({"file": parts[2], "label": parts[3]})

new_files = {item["file"] for item in new_items}
items = [item for item in items if item.get("file") not in new_files]
items.extend(new_items)
items.sort(key=lambda item: item.get("file", ""), reverse=True)

json_path.write_text(
    json.dumps(items, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

# archive 전체에서 파일명상 가장 최근 사진을 current.jpg로 지정합니다.
LATEST_ARCHIVE="$(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.jpg' | sort | tail -n 1)"
if [ -z "${LATEST_ARCHIVE:-}" ]; then
  osascript -e 'display alert "current 지정 실패" message "archive에서 최신 사진을 찾지 못했습니다." as warning'
  exit 1
fi
cp "$LATEST_ARCHIVE" "$CURRENT_FILE"

# 성공한 원본만 incoming에서 제거합니다.
while IFS="$(printf '\t')" read -r LOCAL_TIME SOURCE_FILE TARGET LABEL; do
  [ -n "${SOURCE_FILE:-}" ] && rm -f "$SOURCE_FILE"
done < "$SUCCESS_FILE"

git add -- "$CURRENT_FILE" "$ARCHIVE_DIR" "$ARCHIVE_JSON"

if git commit -m "Update reflection $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
  if git push >/dev/null 2>&1; then
    osascript -e "display notification \"사진 ${SUCCESS_COUNT}장이 업로드되었습니다.\" with title \"시간의 반영\""
    exit 0
  fi
fi

open -a "GitHub Desktop" .
osascript -e "display alert \"사진 처리는 완료되었습니다\" message \"사진 ${SUCCESS_COUNT}장이 archive에 저장되었습니다. GitHub Desktop에서 Push origin을 눌러주세요.\""
