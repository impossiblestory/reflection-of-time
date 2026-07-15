#!/bin/bash
set -u

cd "$(dirname "$0")" || exit 1

INCOMING_DIR="incoming"
ARCHIVE_DIR="archive"
CURRENT_FILE="current.jpg"
ARCHIVE_JSON="archive.json"

mkdir -p "$INCOMING_DIR" "$ARCHIVE_DIR"

SOURCE_FILES=()
while IFS= read -r file; do
  SOURCE_FILES+=("$file")
done < <(
  find "$INCOMING_DIR" -maxdepth 1 -type f \
    ! -name '.DS_Store' \
    ! -name 'README.txt' \
    | sort
)

if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
  osascript -e 'display alert "사진이 없습니다" message "incoming 폴더에 사진을 넣은 뒤 다시 실행하세요." as warning'
  exit 1
fi

WORK_FILE="$(mktemp)"
SUCCESS_FILE="$(mktemp)"
FAILED_FILE="$(mktemp)"
trap 'rm -f "$WORK_FILE" "$SUCCESS_FILE" "$FAILED_FILE"' EXIT

RUN_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

for SOURCE_FILE in "${SOURCE_FILES[@]}"; do
  RAW_DATE="$(mdls -raw -name kMDItemContentCreationDate "$SOURCE_FILE" 2>/dev/null || true)"

  if [[ "$RAW_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    CAPTURE_DATE="${RAW_DATE:0:19}"
  else
    CAPTURE_DATE="$RUN_TIME"
  fi

  printf '%s\t%s\n' "$CAPTURE_DATE" "$SOURCE_FILE" >> "$WORK_FILE"
done

sort "$WORK_FILE" -o "$WORK_FILE"

while IFS=$'\t' read -r CAPTURE_DATE SOURCE_FILE; do
  STAMP="$(date -j -f '%Y-%m-%d %H:%M:%S' "$CAPTURE_DATE" '+%Y%m%d_%H%M%S' 2>/dev/null || date '+%Y%m%d_%H%M%S')"
  LABEL="$(date -j -f '%Y-%m-%d %H:%M:%S' "$CAPTURE_DATE" '+%Y.%m.%d %H:%M:%S' 2>/dev/null || date '+%Y.%m.%d %H:%M:%S')"

  TARGET="$ARCHIVE_DIR/${STAMP}.jpg"
  COUNTER=2
  while [ -e "$TARGET" ]; do
    TARGET="$ARCHIVE_DIR/${STAMP}_${COUNTER}.jpg"
    COUNTER=$((COUNTER + 1))
  done

  if sips -s format jpeg "$SOURCE_FILE" --out "$TARGET" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\t%s\n' "$CAPTURE_DATE" "$SOURCE_FILE" "$TARGET" "$LABEL" >> "$SUCCESS_FILE"
  else
    printf '%s\n' "$SOURCE_FILE" >> "$FAILED_FILE"
  fi
done < "$WORK_FILE"

SUCCESS_COUNT="$(wc -l < "$SUCCESS_FILE" | tr -d ' ')"
FAILED_COUNT="$(wc -l < "$FAILED_FILE" | tr -d ' ')"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
  osascript -e 'display alert "처리 실패" message "사진을 JPEG로 변환하지 못했습니다. incoming 폴더의 파일은 그대로 남아 있습니다." as warning'
  exit 1
fi

LATEST_TARGET="$(tail -n 1 "$SUCCESS_FILE" | cut -f3)"
cp "$LATEST_TARGET" "$CURRENT_FILE"

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
    capture_date, source, target, label = line.split("\t", 3)
    new_items.append({"file": target, "label": label})

new_files = {item["file"] for item in new_items}
items = [item for item in items if item.get("file") not in new_files]
items.extend(new_items)
items.sort(key=lambda item: item.get("file", ""), reverse=True)

json_path.write_text(
    json.dumps(items, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8"
)
PY

while IFS=$'\t' read -r CAPTURE_DATE SOURCE_FILE TARGET LABEL; do
  rm -f "$SOURCE_FILE"
done < "$SUCCESS_FILE"

git add current.jpg archive archive.json display.html index.html
git commit -m "Update reflection $(date '+%Y-%m-%d %H:%M:%S')" || true

if git push; then
  if [ "$FAILED_COUNT" -eq 0 ]; then
    osascript -e "display notification \"사진 ${SUCCESS_COUNT}장이 업로드되었습니다.\" with title \"시간의 반영\""
  else
    osascript -e "display alert \"일부 처리 완료\" message \"사진 ${SUCCESS_COUNT}장은 업로드되었고, 변환하지 못한 ${FAILED_COUNT}장은 incoming 폴더에 남아 있습니다.\" as warning"
  fi
else
  osascript -e 'display alert "업로드 실패" message "사진과 archive 저장은 완료됐지만 git push에 실패했습니다. GitHub Desktop을 열어 Push origin을 눌러주세요." as warning'
  exit 1
fi
