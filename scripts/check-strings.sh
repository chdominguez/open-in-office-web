#!/bin/zsh
# Fails if a L("…") key in Sources/ has no translation in Resources/es.lproj/Localizable.strings.
cd "${0:A:h}/.."
missing=0
grep -ohE 'L\("([^"\\]|\\.)*"' Sources/*.swift | sed -E 's/^L\(//' | sort -u | while read -r key; do
  grep -qF "$key =" Resources/es.lproj/Localizable.strings || { echo "Missing es translation: $key"; missing=1; }
done
exit $missing
