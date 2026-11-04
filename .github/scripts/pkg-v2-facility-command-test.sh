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
  if [ "${consumer_user_env_created-0}" -eq 1 ]
  then
    command -p -- rm -f -- "$consumer_user_env" || :
    command -p -- rmdir -- "$consumer_conf/.m" "$consumer_conf" 2>/dev/null || :
  fi
  if [ "${consumer_binding_set-0}" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider bind -u facility-ci-env-consumer-v2 java >/dev/null 2>&1 || :
  fi
  if [ "${java_default_set-0}" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider default -u java >/dev/null 2>&1 || :
  fi
  command -p -- rm -rf -- "$concrete" "$m_PKG_DIR/facility-ci-java-v2@1" \
    "$m_PKG_DIR/facility-ci-env-consumer-v2@1" "$work"
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
command -p -- mkdir -p "$java_range/facility-bin" "$java_range/facility-env/java" || exit 25
printf 'tar.gz\n' > "$java_range/format"
printf 'java 21\n' > "$java_range/facility"
printf 'bin\n' > "$java_range/facility-bin/java"
printf 'root\n' > "$java_range/facility-env/java/JAVA_HOME"
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

# The provider cannot redefine the central env membership or cardinality.
printf 'literal unexpected\n' > "$java_range/facility-env/java/EXTRA"
if pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root"
then
  exit 37
fi
command -p -- rm -f "$java_range/facility-env/java/EXTRA"
command -p -- mv "$java_range/facility-env/java/JAVA_HOME" "$work/held-JAVA_HOME"
if pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root"
then
  exit 38
fi
command -p -- mv "$work/held-JAVA_HOME" "$java_range/facility-env/java/JAVA_HOME"
printf 'root\nroot\n' > "$java_range/facility-env/java/JAVA_HOME"
if pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root"
then
  exit 39
fi
printf 'root-path ../outside\n' > "$java_range/facility-env/java/JAVA_HOME"
if pkg_facility_provider_validate "$work/catalog/v2" "$java_range" "$work/java-root"
then
  exit 40
fi
printf 'root\n' > "$java_range/facility-env/java/JAVA_HOME"

# A local extension of the copied Java facility contract exercises the
# existing generic PATH projection semantics; the catalog is not modified.
# PATH members are ordered; the later member takes higher precedence.
command -p -- mkdir -p -- "$work/java-root/tools" || exit 45
: > "$work/catalog/v2/facility/java/21/env/PATH" || exit 46
printf 'root-path bin\nroot-path tools\n' > "$java_range/facility-env/java/PATH"

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
[ "$(printf 'JAVA_HOME\troot\nPATH\troot-path bin\nPATH\troot-path tools\n')" = "$(command -p -- cat -- "$java_concrete/facility-env/java")" ] || exit 41

# Exercise the real public default + freshly bootstrapped environment: the
# installed projection is consumed by pkg-provider, not by a parallel context
# environment interpreter.
"$m_ROOT/m" pkg provider default java "$java_name@1" || exit 42
java_default_set=1
JAVA_ROOT_EXPECTED="$java_concrete/root" JAVA_CONCRETE_EXPECTED="$java_concrete" "$m_ROOT/m" sh -ec '
  . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 13
  [ "$JAVA_HOME" = "$JAVA_ROOT_EXPECTED" ] || exit 1

  # Bootstrap gives technical m roots precedence over the global provider
  # projection, while the later PATH record (tools) precedes bin.
  [ "${PATH%%:*}" = "$m_BIN_SYS_OSARCH_DIR" ] || exit 2
  case ":$PATH:" in
    *":$JAVA_ROOT_EXPECTED/tools:$JAVA_ROOT_EXPECTED/bin:"*) : ;;
    *) exit 3 ;;
  esac

  before_context=$PATH
  context "pkg=${JAVA_CONCRETE_EXPECTED##*/}" || exit 4
  [ "${PATH%%:*}" = "$JAVA_CONCRETE_EXPECTED/link/bin" ] || exit 5
  [ "$JAVA_HOME" = "$JAVA_ROOT_EXPECTED" ] || exit 6
  case ":$PATH:" in
    *":$JAVA_ROOT_EXPECTED/tools:$JAVA_ROOT_EXPECTED/bin:"*) : ;;
    *) exit 7 ;;
  esac
  once=$PATH
  context "pkg=${JAVA_CONCRETE_EXPECTED##*/}" || exit 8
  [ "$PATH" = "$once" ] || exit 9
  context || exit 10
  [ "$PATH" = "$before_context" ] || exit 11
  [ "$JAVA_HOME" = "$JAVA_ROOT_EXPECTED" ] || exit 12
' || exit 43

# Exercise a real v2 package-consumer launch. The existing copied Java
# contract is the provider input; all dependency, installation, launcher,
# selected-provider, configuration and execution logic belongs to m itself.
consumer_name=facility-ci-env-consumer-v2
consumer_concrete="$m_PKG_DIR/$consumer_name@1"
[ ! -e "$consumer_concrete" ] && [ ! -L "$consumer_concrete" ] || exit 47
consumer_range="$work/catalog/v2/pkg/$consumer_name/all/n0001=1"
consumer_root="$work/consumer-root"
command -p -- mkdir -p -- "$consumer_range/cmd" "$consumer_range/link/bin" \
  "$consumer_range/link/target" "$consumer_root/bin" || exit 48
printf 'tar.gz\n' > "$consumer_range/format"
printf 'java =21\n' > "$consumer_range/dependency"
printf '../../cmd/ci-env\n' > "$consumer_range/link/bin/ci-env"
printf '../../root/bin/ci-env\n' > "$consumer_range/link/target/ci-env"

cat > "$consumer_range/cmd/ci-env" <<'CI_WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher facility-ci-env-consumer-v2 "$@"
CI_WRAPPER
cat > "$consumer_range/env" <<'CI_PACKAGE_ENV'
JAVA_HOME=ci-consumer-package-home
CI_ENV_LAYER=consumer
PATH="$pkg_launch_root/bin:$PATH"
export JAVA_HOME CI_ENV_LAYER PATH
CI_PACKAGE_ENV
cat > "$consumer_root/bin/ci-env" <<'CI_EXECUTABLE'
#!/bin/sh
[ "$JAVA_HOME" = "$CI_EXPECTED_JAVA_HOME" ] || {
  printf 'FAIL: JAVA_HOME expected=%s observed=%s\n' "$CI_EXPECTED_JAVA_HOME" "$JAVA_HOME" >&2
  exit 1
}
[ "$CI_ENV_LAYER" = "$CI_EXPECTED_LAYER" ] || {
  printf 'FAIL: environment layer expected=%s observed=%s\n' "$CI_EXPECTED_LAYER" "$CI_ENV_LAYER" >&2
  exit 2
}
case "$PATH" in
  "$CI_EXPECTED_PREFIX":*) : ;;
  *)
    printf 'FAIL: PATH prefix expected=%s observed=%s\n' "$CI_EXPECTED_PREFIX" "$PATH" >&2
    exit 3
    ;;
esac
[ "$(command -v javac)" = "$CI_EXPECTED_JAVAC" ] || {
  printf 'FAIL: selected provider javac command unavailable\n' >&2
  exit 4
}
[ "$HOME" = "$CI_EXPECTED_HOME" ] || {
  printf 'FAIL: consumer HOME expected=%s observed=%s\n' "$CI_EXPECTED_HOME" "$HOME" >&2
  exit 5
}
printf '%s\n' 'PASS: consumer package -> selected provider -> user environment -> actual target'
CI_EXECUTABLE
command -p -- chmod +x "$consumer_root/bin/ci-env" || exit 49
pkg_integrate "$consumer_name" 1 "$consumer_range" "$consumer_root" "" v2 \
  "$work/catalog/v2" || exit 50
[ "$(command -p -- cat -- "$consumer_concrete/dependency")" = 'java =21' ] || exit 51
[ "$(command -p -- readlink "$consumer_concrete/link/bin/ci-env")" = ../../cmd/ci-env ] || exit 52

consumer_home="$("$m_ROOT/m" state-path user pkg "$consumer_name" home)" || exit 53
consumer_conf="$("$m_ROOT/m" state-path user pkg "$consumer_name" conf)" || exit 54
consumer_user_env="$consumer_conf/.m/env"
[ ! -e "$consumer_user_env" ] && [ ! -L "$consumer_user_env" ] || exit 55
provider_path="$java_concrete/root/tools:$java_concrete/root/bin"
provider_javac="$java_concrete/root/bin/javac"

CI_EXPECTED_HOME="$consumer_home" CI_EXPECTED_JAVAC="$provider_javac" \
CI_EXPECTED_JAVA_HOME="$java_concrete/root" CI_EXPECTED_LAYER=consumer \
CI_EXPECTED_PREFIX="$provider_path" \
  "$m_ROOT/m" "$consumer_concrete/link/bin/ci-env" || exit 56

command -p -- mkdir -p -- "$consumer_conf/.m" "$work/user-bin" || exit 57
cat > "$consumer_user_env" <<'CI_USER_ENV'
JAVA_HOME=ci-user-home-override
CI_ENV_LAYER=user
PATH="$CI_USER_BIN:$PATH"
export JAVA_HOME CI_ENV_LAYER PATH
CI_USER_ENV
consumer_user_env_created=1
CI_USER_BIN="$work/user-bin" CI_EXPECTED_HOME="$consumer_home" \
CI_EXPECTED_JAVAC="$provider_javac" \
CI_EXPECTED_JAVA_HOME=ci-user-home-override CI_EXPECTED_LAYER=user \
CI_EXPECTED_PREFIX="$work/user-bin:$provider_path" \
  "$m_ROOT/m" "$consumer_concrete/link/bin/ci-env" || exit 58

# A consumer binding must preserve runtime provider application even after
# its independent global default is removed. No re-integration is allowed.
"$m_ROOT/m" pkg provider bind "$consumer_name" java "$java_name@1" || exit 59
consumer_binding_set=1
"$m_ROOT/m" pkg provider default -u java || exit 60
java_default_set=0
CI_USER_BIN="$work/user-bin" CI_EXPECTED_HOME="$consumer_home" \
CI_EXPECTED_JAVAC="$provider_javac" \
CI_EXPECTED_JAVA_HOME=ci-user-home-override CI_EXPECTED_LAYER=user \
CI_EXPECTED_PREFIX="$work/user-bin:$provider_path" \
  "$m_ROOT/m" "$consumer_concrete/link/bin/ci-env" || exit 61
"$m_ROOT/m" pkg provider bind -u "$consumer_name" java || exit 62
consumer_binding_set=0
command -p -- rm -f -- "$consumer_user_env" || exit 63
consumer_user_env_created=0
command -p -- rmdir -- "$consumer_conf/.m" "$consumer_conf" 2>/dev/null || :
command -p -- rm -rf -- "$consumer_concrete" "$java_concrete" || exit 64

printf '%s\n' 'PASS: v2 facility contracts, global PATH/context precedence and normal consumer-launch environment layers'

