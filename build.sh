#!/bin/bash
set -e

# Debian stretch is EOL: deb.debian.org/security.debian.org no longer serve it
# (404 on every index). Point apt at the archive instead. stretch-updates was
# dropped when the release was archived, so it is not listed here.
cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian stretch main
deb http://archive.debian.org/debian-security stretch/updates main
EOF
# Archived Release files are long past their Valid-Until date.
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/10-no-check-valid-until

apt-get update
apt-get install -qy --no-install-recommends \
    netcat \
    libncurses5 \
    libtommath1 \
    libtommath-dev \
    bzip2 \
    ca-certificates \
    curl \
    g++ \
    gcc \
    libicu57 \
    libicu-dev \
    libncurses5-dev \
    libedit2 \
    libedit-dev \
    autoconf \
    automake \
    autotools-dev \
    bison \
    libatomic-ops-dev \
    libtool \
    make

mkdir -p /home/firebird
cd /home/firebird
curl -fL -o firebird-source.tar.bz2 \
    "${FBURL}"
tar --strip=1 -xf firebird-source.tar.bz2
# The bundled config.guess/config.sub predate aarch64 and cannot detect this
# host. These used to be fetched from git.savannah.gnu.org, but that endpoint is
# unreliable (gitweb now 502s and cgit intermittently closes the connection mid
# transfer, failing the build). The autotools-dev package ships versions that
# resolve aarch64-unknown-linux-gnu correctly, with no network dependency.
install -m 0755 /usr/share/misc/config.guess builds/make.new/config/config.guess
install -m 0755 /usr/share/misc/config.sub builds/make.new/config/config.sub
NOCONFIGURE=1 ./autogen.sh
./configure \
        --prefix=${PREFIX} --with-fbbin=${PREFIX}/bin --with-fbsbin=${PREFIX}/bin --with-fblib=${PREFIX}/lib \
        --with-fbinclude=${PREFIX}/include --with-fbdoc=${PREFIX}/doc --with-fbudf=${PREFIX}/UDF \
        --with-fbsample=${PREFIX}/examples --with-fbsample-db=${PREFIX}/examples/empbuild --with-fbhelp=${PREFIX}/help \
        --with-fbintl=${PREFIX}/intl --with-fbmisc=${PREFIX}/misc --with-fbplugins=${PREFIX} \
        --with-fblog=${VOLUME}/log --with-fbglock=/var/firebird/run \
        --with-fbconf=${VOLUME}/etc --with-fbmsg=${PREFIX} \
        --with-fbsecure-db=${VOLUME}/system --with-system-icu --with-system-editline
export CFLAGS=""
export CPPFLAGS=""
export CXXFLAGS="-std=gnu++98"
export FCFLAGS=""
export FFLAGS=""
export GCJFLAGS=""
export LDFLAGS=""
export OBJCFLAGS=""
export OBJCXXFLAGS=""
make
make silent_install
cd /
rm -rf /home/firebird
find ${PREFIX} -name .debug -prune -exec rm -rf {} \;
apt-get purge -qy --auto-remove \
    bzip2 \
    ca-certificates \
    curl \
    g++ \
    gcc \
    libicu-dev \
    libncurses5-dev \
    libtommath-dev \
    make \
    libedit-dev \
    autoconf \
    automake \
    autotools-dev \
    bison \
    libatomic-ops-dev \
    curl
rm -rf /var/lib/apt/lists/*

mkdir -p "${PREFIX}/skel"
mv ${VOLUME}/system/security2.fdb ${PREFIX}/skel/security2.fdb
mv "${VOLUME}/etc" "${PREFIX}/skel"
