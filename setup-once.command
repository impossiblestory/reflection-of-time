#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ ! -d ".git" ]; then
  osascript -e 'display alert "저장소를 찾을 수 없습니다" message "이 파일을 reflection-of-time 저장소의 최상위 폴더에 넣고 실행하세요." as warning'
  exit 1
fi

find . -name '.DS_Store' -type f -delete 2>/dev/null || true

git ls-files -z | while IFS= read -r -d '' f; do
  case "$f" in
    .DS_Store|*/.DS_Store)
      git rm --cached --ignore-unmatch -- "$f" >/dev/null 2>&1 || true
      ;;
  esac
done

git add -A
open -a "GitHub Desktop" .
osascript -e 'display alert "초기 정리가 완료되었습니다" message ".DS_Store를 제거하고 필요한 파일을 스테이징했습니다. GitHub Desktop에서 Summary에 Initial setup을 입력한 뒤 Commit to main과 Push origin을 차례로 누르세요."'
