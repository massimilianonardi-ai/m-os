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



cd "$HOME/m-os-validation/m-os" || exit 1

./m pkg install m-core@v0.1.1
./m pkg install m-term@v0.1.1
./m pkg install m-rsudo@v0.1.2



cd "$HOME/m-os-validation/m-os" || exit 1

./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh"
  context pkg=m-core@v0.1.1 pkg=m-term@v0.1.1
  menu -H "Test m-term" Primo Secondo Terzo
'



cd "$HOME/m-os-validation/m-os" || exit 1

./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh"
  context pkg=m-core@v0.1.1 pkg=m-term@v0.1.1 pkg=m-rsudo@v0.1.2
  rsudo-admin
'



bash -eu <<'SH'
cd "$HOME/m-os-validation/m-os"

echo "=== REVISIONE M-OS ==="
git rev-parse HEAD
git status --short

echo
echo "=== VERSIONE ==="
cat VERSION

echo
echo "=== IDENTITA ==="
id
uname -a

echo
echo "=== SERVIZI SYSTEMD ==="
systemctl list-unit-files --no-legend |
    grep -E '^m-srv-(geoserver|keycloak)\.service[[:space:]]' || :

echo
echo "=== STATO GEOSERVER ==="
systemctl show m-srv-geoserver.service \
    -p LoadState -p ActiveState -p SubState \
    -p User -p ExecStart --no-pager

echo
echo "=== STATO KEYCLOAK ==="
systemctl show m-srv-keycloak.service \
    -p LoadState -p ActiveState -p SubState \
    -p User -p ExecStart --no-pager

echo
echo "=== PROVIDER PREDEFINITI ==="
for service in geoserver keycloak java; do
    echo "--- $service ---"
    ./m pkg provider default "$service" || :
done

echo
echo "=== VERSIONI INSTALLATE ==="
for package in geoserver keycloak temurin; do
    echo "--- $package ---"
    ./m pkg versions "$package" || :
done
SH



cd "$HOME/m-os-validation/m-os" || exit 1

./m pkg provider default geoserver geoserver@3.0.1
./m pkg provider default keycloak keycloak@26.7.3

./m pkg provider default geoserver
./m pkg provider default keycloak

echo "=== ACCOUNT DI SERVIZIO DISPONIBILI ==="

getent passwd |
while IFS=: read -r user password uid gid description home shell; do
    if [ "$uid" -ne 0 ]; then
        case "$shell" in
            */nologin|*/false)
                printf '%-24s UID=%-8s GID=%-8s HOME=%s SHELL=%s\n' \
                    "$user" "$uid" "$gid" "$home" "$shell"
                ;;
        esac
    fi
done

sudo userdel geoserver 2>/dev/null || true
sudo userdel keycloak 2>/dev/null || true

sudo groupdel geoserver 2>/dev/null || true
sudo groupdel keycloak 2>/dev/null || true

sudo groupadd --system geoserver
sudo groupadd --system keycloak

sudo useradd --system \
    --gid geoserver \
    --home-dir /var/lib/geoserver \
    --shell /usr/sbin/nologin \
    geoserver

sudo useradd --system \
    --gid keycloak \
    --home-dir /var/lib/keycloak \
    --shell /usr/sbin/nologin \
    keycloak

id geoserver
id keycloak

sudo userdel geoserver 2>/dev/null || true
sudo userdel keycloak 2>/dev/null || true

sudo groupdel geoserver 2>/dev/null || true
sudo groupdel keycloak 2>/dev/null || true



BASE="$HOME/m-os-validation/m-os"

namei -l "$BASE/m"

cd "$HOME/m-os-validation/m-os" || exit 1

cd "$HOME/m-os-validation/m-os" || exit 1

sudo ./m srv host system stop geoserver
sudo ./m srv host system stop keycloak

sudo ./m srv host system uninstall geoserver
sudo ./m srv host system uninstall keycloak



cd "$HOME/m-os-validation/m-os"

sudo rm -rf -- \
  "$PWD"'/state/system/profile/main/pkg/geoserver@!geoserver/home' \
  "$PWD"'/state/system/profile/main/pkg/keycloak@!keycloak/home'



#sudo ./m srv host system install geoserver geoserver
#sudo ./m srv host system install keycloak keycloak
sudo ./m srv host system install geoserver mnardi
sudo ./m srv host system install keycloak mnardi

sudo ./m srv host system start geoserver
sudo ./m srv host system start keycloak

systemctl status m-srv-geoserver.service --no-pager
systemctl status m-srv-keycloak.service --no-pager

systemctl show m-srv-geoserver.service \
    -p User -p MainPID -p ActiveState

systemctl show m-srv-keycloak.service \
    -p User -p MainPID -p ActiveState

sudo journalctl -u m-srv-geoserver.service -n 30 --no-pager
sudo journalctl -u m-srv-keycloak.service -n 30 --no-pager

curl -i --max-time 30 'http://127.0.0.1:8080/geoserver/ows?service=WFS&version=2.0.0&request=GetCapabilities'
curl -i --max-time 30 'http://127.0.0.1:8080/realms/master/.well-known/openid-configuration'

for service in geoserver keycloak; do
    pid=$(systemctl show "m-srv-$service.service" \
        --property=MainPID --value)

    echo "=== $service PID=$pid ==="

    if [ "$pid" -gt 0 ]; then
        ps -p "$pid" -o user,pid,ppid,args
        sudo readlink -f "/proc/$pid/exe"
    fi
done


sudo ./m srv host system restart geoserver
sudo ./m srv host system restart keycloak

systemctl is-active m-srv-geoserver.service
systemctl is-active m-srv-keycloak.service



sudo ./m srv host system stop geoserver
sudo ./m srv host system stop keycloak

systemctl is-active m-srv-geoserver.service
systemctl is-active m-srv-keycloak.service


