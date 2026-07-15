〈시간의 반영〉 사진 갱신 방법

1. 이 폴더의 파일들을 GitHub 저장소 reflection-of-time의 최상위 폴더에 넣습니다.
2. update.command를 처음 한 번만 터미널에서 실행 가능하게 만듭니다.
   chmod +x update.command
3. 새 사진 한 장을 incoming 폴더에 넣습니다.
4. update.command를 더블클릭합니다.
5. 약 20~30초 뒤 GitHub Pages와 미니빔 화면이 갱신됩니다.

작동 내용
- 촬영 시각을 읽습니다.
- HEIC/PNG/JPEG를 JPEG로 변환합니다.
- current.jpg를 새 사진으로 바꿉니다.
- archive/YYYYMMDD_HHMMSS.jpg로 누적 저장합니다.
- archive.json을 최신순으로 갱신합니다.
- git commit과 git push를 자동 실행합니다.

주의
- incoming 폴더에는 실행할 사진 한 장만 넣는 것이 가장 안전합니다.
- 같은 날 여러 장은 촬영 시각 순으로 정렬됩니다.
- 촬영 시각을 읽지 못하면 실행 시각을 사용합니다.
- GitHub Pages의 배포 원본은 main 브랜치 / root로 설정되어 있어야 합니다.
