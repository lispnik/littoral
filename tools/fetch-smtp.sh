#!/bin/sh
# Check out the smtp library (https://github.com/lispnik/smtp) at the version
# littoral/mail uses, into DIR.  It isn't in the ocicl registry, so CI,
# make clean-check and the Docker builds fetch it with this; its own
# dependencies are in ocicl.csv.  Locally, clone it anywhere ASDF looks.
set -e
ref=v0.3.3
dir=${1:?usage: fetch-smtp.sh DIR}
rm -rf "$dir"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" https://github.com/lispnik/smtp.git "$dir"
