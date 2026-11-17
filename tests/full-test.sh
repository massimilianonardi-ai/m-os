#!/bin/sh



bash -eu <<'SH'
BASE="$HOME/m-os-validation"

if systemctl list-unit-files --no-legend |
   grep -Eq '^m-srv-(geoserver|keycloak)\.service[[:space:]]'; then
    echo "ERRORE: risultano ancora servizi registrati."
    echo "Occorre disinstallarli prima di eliminare l'ambiente."
    exit 1
fi

test "$BASE" = "/home/mnardi/m-os-validation"

cd "$HOME"
sudo rm -rf -- "$BASE"

test ! -e "$BASE"

echo "AMBIENTE ELIMINATO"
SH



bash -eu <<'SH'
BASE="$HOME/m-os-validation"

mkdir -p "$BASE"
cd "$BASE"

git clone --branch master \
    https://github.com/massimilianonardi-ai/m-os.git

git clone --branch main \
    https://github.com/massimilianonardi-ai/pkg-catalog.git

cd "$BASE/m-os"

echo "=== PERMESSI ORIGINALI STATE ==="
stat -c '%a %U:%G %n' state

echo "=== INIZIALIZZAZIONE ==="
./m osarch update

CONF="$(./m state-path system sys pkg conf)"
mkdir -p "$CONF"

printf '%s\n' "$BASE/pkg-catalog" > "$CONF/catalog"

echo "=== PIATTAFORMA ==="
./m osarch show

echo "=== CATALOGO ==="
cat "$CONF/catalog"

echo "AMBIENTE INIZIALIZZATO"
SH



bash -eu <<'SH'
cd "$HOME/m-os-validation/m-os"

echo "=== VERIFICA VERSIONE ==="
git rev-parse HEAD

echo "=== VERIFICA STATE ==="
stat -c '%a %U:%G %n' state

echo "=== VERIFICA COMANDI ==="
./m osarch show
./m state-path system sys pkg conf
./m state-path user sys shell conf

echo "TEST INIZIALIZZAZIONE SUPERATO"
SH



bash -eu <<'SH'
cd "$HOME/m-os-validation/m-os"

./m pkg install nodejs
./m pkg install mk
./m pkg install jsc

./m pkg default mk
./m pkg default jsc

./m pkg install geoserver@3.0.1
./m pkg install keycloak@26.7.3

echo "INSTALLAZIONE PACCHETTI COMPLETATA"
SH

