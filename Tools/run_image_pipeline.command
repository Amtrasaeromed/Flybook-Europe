#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY ist nicht gesetzt."
  echo "Vorher im Terminal ausführen: export OPENAI_API_KEY='…'"
  exit 1
fi

python3 Tools/generate_destination_images.py
python3 Tools/review_destination_images.py
python3 Tools/approve_destination_images.py --create-template

echo
echo "Kandidaten sind erzeugt. Trage in ImageProduction/selections.csv je Ziel"
echo "den Favoriten ein und setze approved auf yes. Danach ausführen:"
echo "python3 Tools/approve_destination_images.py"
