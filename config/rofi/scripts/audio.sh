#!/bin/bash
# Switch PipeWire default sink via rofi

mapfile -t sinks < <(
  wpctl status | awk '
    /^ ├─ Sinks:/      {in_sinks=1; next}
    /^ ├─|^ └─/        {in_sinks=0}
    in_sinks && /[0-9]+\./ {
      is_current = ($0 ~ /\*/) ? 1 : 0
      match($0, /[0-9]+\./); id=substr($0,RSTART,RLENGTH-1)
      sub(/.*[0-9]+\. /,""); sub(/ *\[vol:.*/,"")
      print id "\t" is_current "\t" $0
    }'
)

menu=$(printf '%s\n' "${sinks[@]}" | awk -F'\t' '{
  if ($2 == "1") print "<span foreground=\"#c4a7e7\">" $3 "</span>"
  else print $3
}')

selected=$(echo "$menu" | rofi -dmenu -i -markup-rows -p "󱄠" -theme ~/.config/rofi/themes/audio.rasi | sed -E 's|<[^>]+>||g')
[ -z "$selected" ] && exit

for row in "${sinks[@]}"; do
  IFS=$'\t' read -r id _cur name <<< "$row"
  if [ "$name" = "$selected" ]; then
    wpctl set-default "$id"
    break
  fi
done
