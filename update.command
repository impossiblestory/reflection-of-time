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

  # Spotlight가 반환하는 UTC 시각(+0000)을 Mac의 현지 시간대로 변환합니다.
  LOCAL_TIME="$(python3 - "$SOURCE_FILE" <<'PY'
import subprocess
import sys
from datetime import datetime
from pathlib import Path

path = sys.argv[1]

def read_mdls(key: str) -> str:
    result = subprocess.run(
        ["mdls", "-raw", "-name", key, path],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()

raw = read_mdls("kMDItemContentCreationDate")
if not raw or raw == "(null)":
    raw = read_mdls("kMDItemFSCreationDate")

dt = None
for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S"):
    try:
        dt = datetime.strptime(raw, fmt)
        break
    except ValueError:
        pass

if dt is None:
    dt = datetime.now().astimezone()
elif dt.tzinfo is not None:
    dt = dt.astimezone()
else:
    dt = dt.astimezone()

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
