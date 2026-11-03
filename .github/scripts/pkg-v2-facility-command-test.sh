#!/bin/sh
# Validate one real v2 contract against a fixture provider binary directory.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${CATALOG_V2-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

work=$(mktemp -d) || exit 4
name=facility-ci-node-v2
concrete="$m_PKG_DIR/$name@1"
cleanup()
{
  command -p -- rm -rf -- "$concrete" "$m_PKG_DIR/facility-ci-java-v2@1" "$work"
}
[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
trap cleanup 0
command -p -- mkdir -p -- "$m_PKG_DIR" "$work/catalog/v2/pkg/$name/all" \
  "$work/catalog/v2/facility" "$work/root/bin" || exit 6
command -p -- cp -R -- "$CATALOG_V2/facility/nodejs" "$work/catalog/v2/facility/nodejs" || exit 7
range="$work/catalog/v2/pkg/$name/all/n0001=1"
command -p -- mkdir -p -- "$range/facility-bin" || exit 8
printf 'tar.gz\n' > "$range/format"
printf 'nodejs 26\n' > "$range/facility"
printf 'bin\n' > "$range/facility-bin/nodejs"
cat > "$work/root/bin/node" <<'EXE'
#!/bin/sh
printf 'fixture-node-v2\n'
EXE
command -p -- chmod +x "$work/root/bin/node" || exit 9

pkg_facility_provider_validate "$work/catalog/v2" "$range" "$work/root" || exit 10
pkg_integrate "$name" 1 "$range" "$work/root" "" v2 "$work/catalog/v2" || exit 11
[ "$(command -p -- cat -- "$concrete/schema")" = v2 ] || exit 12
[ "$(command -p -- readlink "$concrete/link/bin/node")" = "../../root/bin/node" ] || exit 13
[ "$(command -p -- readlink "$concrete/facility-cmd/nodejs/node")" = "../../link/bin/node" ] || exit 14
[ "$("$concrete/link/bin/node")" = fixture-node-v2 ] || exit 15
[ "$("$concrete/facility-cmd/nodejs/node")" = fixture-node-v2 ] || exit 16

# The normal public provider default publishes exactly the facility command.
"$m_ROOT/m" pkg provider default nodejs "$name@1" || exit 19
[ "$("$m_ROOT/m" node)" = fixture-node-v2 ] || exit 20
case "$(command -p -- readlink "$m_BIN_EXT_DIR/node")" in ../../pkg/*/link/bin/node) : ;; *) exit 36 ;; esac
"$m_ROOT/m" pkg provider default -u nodejs || exit 21

command -p -- rm -f -- "$concrete/root/bin/node" || exit 17
if pkg_facility_provider_validate "$work/catalog/v2" "$range" "$concrete/root"
then
  exit 18
fi


# The Java contract contains many required commands, but only one parameter
# appears in the provider range; all command links are synthesized by pkg.
java_name=facility-ci-java-v2
java_concrete="$m_PKG_DIR/$java_name@1"
[ ! -e "$java_concrete" ] && [ ! -L "$java_concrete" ] || exit 22
command -p -- mkdir -p "$work/catalog/v2/pkg/$java_name/all" "$work/java-root/bin" || exit 23
command -p -- cp -R "$CATALOG_V2/facility/java" "$work/catalog/v2/facility/java" || exit 24
java_range="$work/catalog/v2/pkg/$java_name/all/n0001=1"
command -p -- mkdir -p "$java_range/facility-bin" "$java_range/facility-env" || exit 25
printf 'tar.gz\n' > "$java_range/format"
printf 'java 21\n' > "$java_range/facility"
printf 'bin\n' > "$java_range/facility-bin/java"
printf 'JAVA_HOME\troot\n' > "$java_range/facility-env/java"
for member in "$work/catalog/v2/facility/java/21/cmd/"*
do
  command_name=${member##*/}
  printf '#!/bin/sh\nprintf "fixture-java\\n"\n' > "$work/java-root/bin/$command_name"
  command -p -- chmod +x "$work/java-root/bin/$command_name" || exit 26
done

command -p -- rm -f "$work/java-root/bin/javac" || exit 27
if pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root"
then
  exit 28
fi
printf '#!/bin/sh\nprintf "fixture-java\\n"\n' > "$work/java-root/bin/javac"
command -p -- chmod +x "$work/java-root/bin/javac" || exit 29

pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root" || exit 30
pkg_integrate "$java_name" 1 "$java_range" "$work/java-root" "" v2 "$work/catalog/v2" || exit 31
for member in "$work/catalog/v2/facility/java/21/cmd/"*
do
  command_name=${member##*/}
  [ -L "$java_concrete/link/bin/$command_name" ] || exit 32
  [ -L "$java_concrete/facility-cmd/java/$command_name" ] || exit 33
done
[ "$("$java_concrete/link/bin/javac")" = fixture-java ] || exit 34
[ -f "$java_concrete/facility-env/java" ] || exit 35
command -p -- rm -rf "$java_concrete"

printf '%s\n' 'PASS: central nodejs and Java facility contracts, provider parameters and public command mapping'

