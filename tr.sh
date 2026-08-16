#!/usr/bin/env bash
# Tek giriş noktası — her platformda çalışır.
# Windows'ta 'make' olmadığı için Git Bash'te bunu kullan:
#
#   ./tr.sh tools     araçları indir
#   ./tr.sh pull      APK'yı telefondan çek
#   ./tr.sh patch     manifest yaması + imza
#   ./tr.sh install   orijinali kaldır, yamalıyı kur
#   ./tr.sh all       yukarıdaki dördü sırayla
#   ./tr.sh prefs [list|guess|get K|set K V|add K N|savekeys ..|loadkeys F|backup]
#   ./tr.sh info      motor tespiti (Mono / IL2CPP)
#   ./tr.sh dump      IL2CPP dokumu (PC tarafinda, opsiyonel)
#   ./tr.sh menu      oyun ici MOD MENUSUNU APK'ya enjekte et (bir kez)
#   ./tr.sh agent     menu ajanini telefona gonder (log|classes|dump)
#   ./tr.sh test      cihazsız kendi kendine test

cd "$(dirname "$0")" || exit 1

CMD="${1:-help}"; shift || true

case "$CMD" in
  tools)   exec ./tools/00-fetch-tools.sh "$@" ;;
  pull)    exec ./tools/01-pull.sh "$@" ;;
  patch)   exec ./tools/02-patch.sh "$@" ;;
  install) exec ./tools/03-install.sh "$@" ;;
  prefs)   exec ./tools/04-prefs.sh "${@:-list}" ;;
  info)    exec ./tools/05-engine-info.sh "$@" ;;
  dump)    exec ./tools/06-dump.sh "$@" ;;
  menu)    exec ./tools/07-menu.sh "$@" ;;
  agent)   exec ./tools/08-agent.sh "$@" ;;
  test)    exec ./tools/selftest.sh "$@" ;;
  all)
    ./tools/00-fetch-tools.sh && \
    ./tools/01-pull.sh && \
    ./tools/02-patch.sh && \
    ./tools/03-install.sh
    ;;
  help|-h|--help|"")
    # baştaki yorum bloğunu yaz (shebang hariç, ilk kod satırında dur)
    awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
    ;;
  *)
    echo "Bilinmeyen komut: $CMD" >&2
    echo "Kullanılabilir: tools pull patch install all prefs info dump menu agent test" >&2
    exit 1
    ;;
esac
