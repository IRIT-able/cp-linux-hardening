#!/usr/bin/env bash
# 70-media.sh - prohibited media files. Catalog: "Prohibited media files".
# Audio/video under /home is offered for deletion one directory at a time. Everything else is reported only.
# Deleted media is NOT copied to the backup folder (a copy would still be a prohibited file): the VM snapshot is the backup.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "MEDIA" "$@"

AV_EXT=(mp3 mp4 ogg oga ogv opus wav flac aac m4a m4v wma wmv avi mkv mov webm flv mpg mpeg 3gp mid midi)
IMG_EXT=(jpg jpeg png gif bmp tif tiff webp)
PRUNE=( \( -path '*/.cache' -o -path '*/snap' -o -path '*/.mozilla' -o -path '*/.thunderbird' -o -path '*/.local/share/icons' -o -path '*/.config' \) -prune -o )

name_expr() { NAME_EXPR=(); local e first=1; for e in "$@"; do (( first )) || NAME_EXPR+=(-o); NAME_EXPR+=(-iname "*.$e"); first=0; done; }
kept_path() { local k; for k in "${MEDIA_KEEP_PATHS[@]}"; do [[ $1 == "$k" || $1 == "$k"/* ]] && return 0; done; return 1; }

# ---------- audio and video ----------
section "Audio and video files"
name_expr "${AV_EXT[@]}"
mapfile -d '' -t AV < <(find /home /root /srv /var/www /opt /tmp /var/tmp /media /mnt -xdev "${PRUNE[@]}" -type f \( "${NAME_EXPR[@]}" \) -print0 2>/dev/null)
declare -A BYDIR=()
for f in "${AV[@]}"; do
  is_protected_path "$f" && continue
  d=$(dirname "$f"); BYDIR[$d]+="$f"$'\n'
done
(( ${#BYDIR[@]} )) || ok "no audio or video files found in home, service or temp directories"
for d in "${!BYDIR[@]}"; do
  mapfile -t files < <(printf '%s' "${BYDIR[$d]}")
  n=${#files[@]}
  printf '%s\n' "${files[@]}" | sed 's/^/      /' | tee -a "$CP_LOG"
  if kept_path "$d"; then
    report "$n media file(s) in $d - under MEDIA_KEEP_PATHS, never deleted here (deleting service content was a penalty in two keys)"
  elif [[ $d == */.local/share/Trash/* ]]; then
    report "$n media file(s) in the Trash at $d - a forensics question may need them; empty the Trash by hand afterwards"
  elif [[ $d != /home/* ]]; then
    report "$n media file(s) in $d - outside /home, so not deleted automatically; decide by hand"
  elif ! is_apply; then
    would "delete $n audio/video file(s) in $d (you will be asked per directory)"
  else
    forensics_gate "delete media in $d" || continue
    confirm "Delete the $n audio/video file(s) listed above in $d?" || continue
    for f in "${files[@]}"; do
      printf 'deleting %s (%s bytes, sha256 %s)\n' "$f" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" >>"$CP_LOG"
    done
    fix "delete $n audio/video file(s) in $d" rm -f -- "${files[@]}"
  fi
done

# ---------- images ----------
section "Images in home directories (report only: wallpapers and work files are normal)"
name_expr "${IMG_EXT[@]}"
while read -r n d; do report "$n image(s) in $d"; done < <(
  find /home /root -xdev "${PRUNE[@]}" -type f \( "${NAME_EXPR[@]}" \) -printf '%h\n' 2>/dev/null | sort | uniq -c | sort -rn | head -40)

# ---------- media hiding behind another name ----------
section "Files whose content is audio/video but whose name is not (report only)"
name_expr "${AV_EXT[@]}"
while IFS= read -r -d '' f; do
  case $(file -b --mime-type "$f" 2>/dev/null) in audio/*|video/*) report "media content under another name: $f" ;; esac
done < <(find /home /root -xdev "${PRUNE[@]}" -type f -size +100k ! \( "${NAME_EXPR[@]}" \) -print0 2>/dev/null)

section "Hidden files and directories directly inside home directories (report only)"
for h in /home/*; do
  [[ -d $h ]] || continue
  extra=$(find "$h" -maxdepth 1 -name '.*' ! -name . ! -name .. \
            ! -name '.bash*' ! -name .profile ! -name .cache ! -name .config ! -name .local ! -name .mozilla \
            ! -name .thunderbird ! -name .gnupg ! -name .ssh ! -name .sudo_as_admin_successful ! -name '.xsession*' \
            ! -name .pki ! -name .dbus ! -name .gvfs ! -name '.ICEauthority' ! -name '.Xauthority' ! -name .dmrc \
            ! -name .linuxmint ! -name .cinnamon ! -name .mate ! -name .themes ! -name .icons ! -name '.gtkrc*' \
            ! -name .lesshst ! -name .wget-hsts ! -name .selected_editor ! -name .xinputrc ! -name '.face*' \
            -printf '%f ' 2>/dev/null)
  [[ -n $extra ]] && report "$h has unusual hidden entries: $extra"
done
cp_done
