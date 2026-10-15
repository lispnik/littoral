#!/bin/sh
# Build the Seaside image bench/compare.sh seaside runs:
#   bench/seaside/setup.sh DIR
# Downloads Pharo 12 and its VM into DIR, loads Seaside (the default group,
# from a clone of github.com/SeasideSt/Seaside) and files in
# littoral-bench.st.  Needs git and curl.
set -e
dir=${1:?usage: setup.sh DIR}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$dir" && cd "$dir"
[ -f Pharo.image ] || curl -sL https://get.pharo.org/64/120+vm | bash
# Iceberg's own clone of the baseline fails on GitHub's SSH rules, so clone
# over HTTPS and point Metacello at it; dependencies then come over HTTPS.
[ -d seaside-src ] || git clone -q https://github.com/SeasideSt/Seaside.git seaside-src
cat > load.st <<ST
Iceberg remoteTypeSelector: #httpsUrl.
Metacello new
  baseline: 'Seaside3';
  repository: 'gitlocal://$PWD/seaside-src/repository';
  load: #('default').
Smalltalk snapshot: true andQuit: true.
ST
# The classes filed in here don't exist when this compiles: hence at:.
cat > register.st <<ST
CodeImporter evaluateFileNamed: '$here/littoral-bench.st'.
(Smalltalk at: #LtBenchFiles) addFileNamed: 'littoral.js'
  contents: '$here/../../static/littoral.js' asFileReference contents.
WAAdmin disableDevelopmentTools.
WAAdmin register: WACounter asApplicationAt: 'counter'.
WAAdmin register: (Smalltalk at: #LtStore) asApplicationAt: 'store'.
WAAdmin defaultDispatcher register: (Smalltalk at: #LtStatsHandler) new at: '_stats'.
Smalltalk snapshot: true andQuit: true.
ST
./pharo Pharo.image st --quit load.st
./pharo Pharo.image st --quit register.st
