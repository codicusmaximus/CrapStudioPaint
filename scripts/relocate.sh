# Make a prefix built under one Linux user work under another.
# Wine keys the Windows profile on $USER (C:\users\<name>). When the prefix is
# moved to a machine with a different username, rename the profile directory
# and rewrite the registry paths so CSP keeps its settings.
relocate_prefix_user() {
  local stamp="$WINEPREFIX/.csp-user" old new="$USER"
  [[ -d "$WINEPREFIX/drive_c/users" ]] || return 0
  if [[ ! -f "$stamp" ]]; then echo "$new" > "$stamp"; return 0; fi
  old=$(<"$stamp")
  [[ "$old" == "$new" ]] && return 0
  echo "Relocating prefix profile: $old -> $new" >&2
  "$WINESERVER" -k 2>/dev/null || true
  local users="$WINEPREFIX/drive_c/users"
  if [[ -d "$users/$old" && ! -e "$users/$new" ]]; then
    mv "$users/$old" "$users/$new"
  fi
  # Documents/Desktop/... are symlinks into the old user's home; repoint them.
  local l t
  while IFS= read -r -d '' l; do
    t=$(readlink "$l")
    if [[ "$t" == /home/"$old"/* ]]; then
      ln -sfn "$HOME/${t#/home/"$old"/}" "$l"
    fi
  done < <(find "$users/$new" -type l -print0 2>/dev/null)
  local f
  for f in "$WINEPREFIX"/{system,user,userdef}.reg; do
    [[ -f "$f" ]] && sed -i "s/\\\\\\\\users\\\\\\\\${old}\\b/\\\\\\\\users\\\\\\\\${new}/Ig; s#/home/${old}/#/home/${new}/#g" "$f"
  done
  echo "$new" > "$stamp"
}
